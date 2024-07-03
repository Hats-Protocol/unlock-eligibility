// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { IPublicLock, PublicLockV14Eligibility } from "../src/PublicLockV14Eligibility.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { HatsModuleFactory, IHats } from "hats-module/utils/DeployFunctions.sol";
import { Deploy, DeployInstance } from "../script/Deploy.s.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { HatsErrors } from "hats-protocol/Interfaces/HatsErrors.sol";

contract PublicLockV14EligibilityTest is Deploy, Test {
  /// @dev Inherit from DeployPrecompiled instead of Deploy if working with pre-compiled contracts

  /// @dev variables inhereted from Deploy script
  // UnlockV14Eligibility public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 19_467_227; // deployment block for HatsModuleFactory v0.7.0
  string public NETWORK = "mainnet";
  IHats public HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  HatsModuleFactory public factory;
  PublicLockV14Eligibility public instance;
  bytes public otherImmutableArgs;
  bytes public initArgs;
  uint256 saltNonce;

  DeployInstance public deployInstance;

  IUnlock public unlockFactory = IUnlock(0xe79B93f8E22676774F2A8dAd469175ebd00029FA); // UnlockFactory on mainnet
  IPublicLock public lock;

  address public referrer = makeAddr("referrer");
  uint256 public referrerFeePercentage = 1000; // 10%
  address public lockManager = makeAddr("lock manager");

  uint16 public lockVersion = 14;

  address public org = makeAddr("org");
  address public wearer = makeAddr("wearer");
  address public nonWearer = makeAddr("non-wearer");

  uint256 public tophat;
  uint256 public adminHat; // should be worn by {instance}
  uint256 public targetHat; // should be worn by {wearer}

  // lock init data
  PublicLockV14Eligibility.LockConfig lockConfig;

  string public MODULE_VERSION;

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = _createForkForNetwork(NETWORK);

    // deploy implementation via the script
    prepare(false, MODULE_VERSION, referrer, referrerFeePercentage);
    run();
  }

  function _getUnlockDeploymentBlock(bytes memory _deploymentData) internal pure returns (uint256) {
    (,, uint256 blockNumber) = abi.decode(_deploymentData, (uint256, address, uint256));
    return blockNumber;
  }

  function _getHatsModuleFactoryDeploymentBlock(bytes memory _deploymentData) internal pure returns (uint256) {
    (uint256 blockNumber,,) = abi.decode(_deploymentData, (uint256, address, uint256));
    return blockNumber;
  }

  function _getChainIdForNetwork(string memory _network) internal view returns (uint256) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/script/Chains.json");
    string memory json = vm.readFile(path);
    string memory network = string.concat(".", _network);
    bytes memory data = vm.parseJson(json, network);
    return abi.decode(data, (uint256));
  }

  function _getForkBlockForNetwork(string memory _network) internal view returns (uint256) {
    // get the chainid for the network
    uint256 chainId = _getChainIdForNetwork(_network);

    // get the deployment data for the network
    bytes memory deploymentData = Deploy.getDeploymentDataForNetwork(chainId);
    uint256 unlockBlock = _getUnlockDeploymentBlock(deploymentData);
    uint256 hatsModuleFactoryBlock = _getHatsModuleFactoryDeploymentBlock(deploymentData);
    // return the higher of unlock deployment block and hats module factory deployment block
    return unlockBlock > hatsModuleFactoryBlock ? unlockBlock : hatsModuleFactoryBlock;
  }

  function _createForkForNetwork(string memory _network) internal returns (uint256) {
    return vm.createSelectFork(vm.rpcUrl(_network), _getForkBlockForNetwork(_network));
  }

  function test_mainnet() public {
    _createForkForNetwork("mainnet");
  }
}

contract WithInstanceTest is PublicLockV14EligibilityTest {
  function setUp() public virtual override {
    super.setUp();

    // set the salt nonce
    saltNonce = 1;

    // set lock init data
    lockConfig = PublicLockV14Eligibility.LockConfig({
      expirationDuration: 1 days, // 1 day
      tokenAddress: address(0), // ETH
      keyPrice: 1 ether, // 1 ETH
      maxNumberOfKeys: 10, // 10 keys
      lockManager: lockManager,
      lockName: "Unlock Eligibility Test"
    });

    // set up the hats
    tophat = HATS.mintTopHat(org, "test", "test");
    vm.startPrank(org);
    adminHat = HATS.createHat(tophat, "adminHat", 1, address(1), address(1), true, "test");
    targetHat = HATS.createHat(adminHat, "targetHat", 1, address(1), address(1), true, "test");
    vm.stopPrank();

    // deploy the instance using the script; this will also create a new lock
    deployInstance = new DeployInstance();
    deployInstance.prepare(false, address(implementation), targetHat, saltNonce, lockConfig);
    instance = deployInstance.run();

    // mint the adminHat to the instance so that it can mint the targetHat
    vm.prank(org);
    HATS.mintHat(adminHat, address(instance));

    // update the targetHat's eligibility to the instance
    vm.prank(org);
    HATS.changeHatEligibility(targetHat, address(instance));
  }

  /// @dev Purchase a single key from a given lock for a given recipient
  /// @return The tokenId of the purchased key
  function _purchaseSingleKey(IPublicLock _lock, address _recipient) internal returns (uint256) {
    // give the recipient some ETH
    deal(_recipient, 1 ether);

    // set up the purchase data
    uint256[] memory _values = new uint256[](1);
    _values[0] = _lock.keyPrice();
    address[] memory _recipients = new address[](1);
    _recipients[0] = _recipient;
    address[] memory _referrers = new address[](1);
    _referrers[0] = address(0);
    address[] memory _keyManagers = new address[](1);
    _keyManagers[0] = address(0);
    bytes[] memory _data = new bytes[](1);
    _data[0] = abi.encode(0);

    // the return array
    uint256[] memory _tokenIds = new uint256[](1);

    // make the purchase, passing in the correct eth value
    vm.prank(_recipient);
    _tokenIds = _lock.purchase{ value: _values[0] }(_values, _recipients, _referrers, _keyManagers, _data);

    return _tokenIds[0];
  }

  function _getLock() internal view returns (IPublicLock) {
    return IPublicLock(instance.lock());
  }
}

contract Deployment is WithInstanceTest {
  /// @dev ensure that both the implementation and instance are properly initialized
  function test_initialization() public {
    // implementation
    vm.expectRevert("Initializable: contract is already initialized");
    implementation.setUp("setUp attempt");
    // instance
    vm.expectRevert("Initializable: contract is already initialized");
    instance.setUp("setUp attempt");
  }

  function test_version() public view {
    assertEq(instance.version(), MODULE_VERSION);
  }

  function test_implementation() public view {
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_hats() public view {
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_hatId() public view {
    assertEq(instance.hatId(), targetHat);
  }

  function test_referrerFeePercentage() public view {
    assertEq(instance.REFERRER_FEE_PERCENTAGE(), referrerFeePercentage);
  }

  function test_referrer() public view {
    assertEq(instance.REFERRER(), referrer);
  }

  function test_createLock() public {
    lock = IPublicLock(instance.lock());

    // lock config
    assertTrue(lock.isLockManager(address(lockManager)));
    assertFalse(lock.isLockManager(address(instance)));
    assertEq(lock.keyPrice(), lockConfig.keyPrice);
    assertEq(lock.maxNumberOfKeys(), lockConfig.maxNumberOfKeys);
    assertEq(lock.expirationDuration(), lockConfig.expirationDuration);
    assertEq(lock.name(), lockConfig.lockName);
    assertEq(lock.tokenAddress(), lockConfig.tokenAddress);
    assertEq(lock.onKeyPurchaseHook(), address(instance));

    // lock version
    assertEq(lock.publicLockVersion(), lockVersion);
  }
}

contract DeploymentArbitrum is Deployment {
  function setUp() public override {
    // create a new fork for arbitrum
    fork = _createForkForNetwork("arbitrum");

    super.setUp();
  }

  function test_arbitrum() public {
    test_createLock();
  }
}

contract DeploymentBase is Deployment {
  function setUp() public override {
    // create a new fork for base
    fork = _createForkForNetwork("base");

    super.setUp();
  }

  function test_base() public {
    test_createLock();
  }
}

contract DeploymentCelo is Deployment {
  function setUp() public override {
    // create a new fork for celo
    fork = _createForkForNetwork("celo");

    super.setUp();
  }

  function test_celo() public {
    test_createLock();
  }
}

contract DeploymentGnosis is Deployment {
  function setUp() public override {
    // create a new fork for gnosis
    fork = _createForkForNetwork("gnosis");

    super.setUp();
  }

  function test_gnosis() public {
    test_createLock();
  }
}

contract DeploymentOptimism is Deployment {
  function setUp() public override {
    // create a new fork for optimism
    fork = _createForkForNetwork("optimism");

    super.setUp();
  }

  function test_optimism() public {
    test_createLock();
  }
}

contract DeploymentPolygon is Deployment {
  function setUp() public override {
    // create a new fork for polygon
    fork = _createForkForNetwork("polygon");

    super.setUp();
  }

  function test_polygon() public {
    test_createLock();
  }
}

contract DeploymentSepolia is Deployment {
  function setUp() public override {
    // create a new fork for sepolia
    fork = _createForkForNetwork("sepolia");

    super.setUp();
  }

  function test_sepolia() public {
    test_createLock();
  }
}

contract KeyPurchasePrice is WithInstanceTest {
  function test_happy() public view {
    uint256 price = instance.keyPurchasePrice(address(0), address(0), address(0), bytes(""));
    assertEq(price, lockConfig.keyPrice);
  }

  function test_revert_invalidReferrerFee() public {
    lock = _getLock();

    // change the referrer fee on the lock
    vm.prank(lockManager);
    lock.setReferrerFee(referrer, referrerFeePercentage - 1);

    console2.log("referrer fee set");

    // the purchase price should revert
    vm.expectRevert(PublicLockV14Eligibility.InvalidReferrerFee.selector);
    instance.keyPurchasePrice(address(0), address(0), address(0), bytes(""));
  }
}

contract OnKeyPurchase is WithInstanceTest {
  function test_happy() public {
    lock = _getLock();

    // should revert because we're shortcutting the typical flow and calling this function without actually purchasing a
    // key, and so the wearer is not eligible and therefore cannot be minted the hat
    vm.expectRevert(PublicLockV14Eligibility.HatMintFailed.selector);

    vm.prank(address(lock));
    instance.onKeyPurchase(0, address(0), wearer, address(0), bytes(""), 0, 0);

    // the wearer should not have the hat
    assertFalse(HATS.isWearerOfHat(wearer, targetHat));
  }

  /// @dev This test will follow the natural flow of calling the hook from inside the lock puchase function
  function test_succeed_alreadyWearingHat() public {
    lock = _getLock();

    // increase the hat's max supply
    vm.prank(org);
    HATS.changeHatMaxSupply(targetHat, 100);

    // remove the hat's eligibility module
    vm.prank(org);
    HATS.changeHatEligibility(targetHat, address(1));

    // manually mint the wearer a hat, so the supply of the hat is 1
    vm.prank(org);
    HATS.mintHat(targetHat, wearer);
    assertEq(HATS.hatSupply(targetHat), 1);

    // replace the eligibility module
    vm.prank(org);
    HATS.changeHatEligibility(targetHat, address(instance));

    // since the wearer doesn't have a key, they should no longer be eligible, and therefore should not have the hat
    assertFalse(lock.getHasValidKey(wearer));
    (bool eligible, bool standing) = instance.getWearerStatus(wearer, targetHat);
    assertFalse(eligible);
    assertTrue(standing);
    assertFalse(HATS.isWearerOfHat(wearer, targetHat));
    // note that this doesn't change the hat's supply since the hat was only dynamically revoked, not fully burned
    assertEq(HATS.hatSupply(targetHat), 1);

    // now purchase a key for the wearer; this should succeed even though they already have a static balance of the hat
    _purchaseSingleKey(lock, wearer);

    // the wearer should now have a key, be eligible, and have the hat
    assertTrue(lock.getHasValidKey(wearer));
    (eligible, standing) = instance.getWearerStatus(wearer, targetHat);
    assertTrue(eligible);
    assertTrue(standing);
    assertTrue(HATS.isWearerOfHat(wearer, targetHat));

    // the hat supply should still be 1
    assertEq(HATS.hatSupply(targetHat), 1);
  }

  function test_revert_notLock() public {
    vm.expectRevert(PublicLockV14Eligibility.NotLock.selector);
    instance.onKeyPurchase(0, address(0), wearer, address(0), bytes(""), 0, 0);
  }
}

contract GetWearerStatus is WithInstanceTest {
  function setUp() public override {
    super.setUp();

    lock = _getLock();
  }

  function test_purchased_unexpired() public {
    // purchase a key for the wearer
    _purchaseSingleKey(lock, wearer);

    // the wearer should have both the key and the hat
    assertTrue(lock.getHasValidKey(wearer));
    assertTrue(HATS.isWearerOfHat(wearer, targetHat));

    // the wearer should be eligible
    (bool eligible, bool standing) = instance.getWearerStatus(wearer, targetHat);
    assertTrue(eligible);
    assertTrue(standing);
  }

  function test_purchased_expired() public {
    // purchase a key for the wearer
    uint256 key = _purchaseSingleKey(lock, wearer);

    // the wearer should be eligible

    (bool eligible, bool standing) = instance.getWearerStatus(wearer, targetHat);
    assertTrue(eligible);
    assertTrue(standing);

    // get the expiration timestamp for the key
    uint256 expiration = lock.keyExpirationTimestampFor(key);

    // warp the time forward to the just before expiration
    vm.warp(expiration - 1);

    // the wearer should still be eligible
    (eligible, standing) = instance.getWearerStatus(wearer, targetHat);
    assertTrue(eligible);
    assertTrue(standing);

    // warp the time forward to the expiration
    vm.warp(expiration);

    // the wearer should not be eligible
    (eligible, standing) = instance.getWearerStatus(wearer, targetHat);
    assertFalse(eligible);
    assertTrue(standing);
  }

  function test_unpurchased() public view {
    // the wearer should not have a key
    assertFalse(lock.getHasValidKey(wearer));

    // the wearer should not be eligible
    (bool eligible, bool standing) = instance.getWearerStatus(wearer, targetHat);
    assertFalse(eligible);
    assertTrue(standing);
  }
}

contract Transfers is WithInstanceTest {
  function test_revert_transfer() public {
    lock = _getLock();

    // purchase a key for the wearer
    uint256 tokenId = _purchaseSingleKey(lock, wearer);

    // transfer the key to the non-wearer, expecting a revert
    vm.expectRevert(PublicLockV14Eligibility.NotTransferable.selector);
    vm.prank(wearer);
    lock.transferFrom(wearer, nonWearer, tokenId);
  }
}
