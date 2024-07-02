// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { IPublicLock, UnlockEligibility } from "../src/UnlockEligibility.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { HatsModuleFactory, IHats } from "hats-module/utils/DeployFunctions.sol";
import { Deploy, DeployInstance } from "../script/Deploy.s.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { HatsErrors } from "hats-protocol/Interfaces/HatsErrors.sol";

contract UnlockEligibilityTest is Deploy, Test {
  /// @dev Inherit from DeployPrecompiled instead of Deploy if working with pre-compiled contracts

  /// @dev variables inhereted from Deploy script
  // UnlockEligibility public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 19_467_227; // deployment block for HatsModuleFactory v0.7.0
  string public NETWORK = "mainnet";
  IHats public HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  HatsModuleFactory public factory;
  UnlockEligibility public instance;
  bytes public otherImmutableArgs;
  bytes public initArgs;
  uint256 saltNonce;

  DeployInstance public deployInstance;

  IUnlock public unlockFactory = IUnlock(0xe79B93f8E22676774F2A8dAd469175ebd00029FA); // UnlockFactory on mainnet
  IPublicLock public lock;

  address public feeSplitRecipient = makeAddr("fee split recipient");
  uint256 public feeSplitPercentage = 1000; // 10%
  address public lockManager = makeAddr("lock manager");

  address public org = makeAddr("org");
  address public wearer = makeAddr("wearer");
  address public nonWearer = makeAddr("non-wearer");

  uint256 public tophat;
  uint256 public adminHat; // should be worn by {instance}
  uint256 public targetHat; // should be worn by {wearer}

  // lock init data
  UnlockEligibility.LockConfig lockConfig;

  string public MODULE_VERSION;

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl(NETWORK), BLOCK_NUMBER);

    // deploy implementation via the script
    prepare(false, MODULE_VERSION, feeSplitRecipient, feeSplitPercentage);
    run();
  }
}

contract WithInstanceTest is UnlockEligibilityTest {
  function setUp() public virtual override {
    super.setUp();

    // set the salt nonce
    saltNonce = 1;

    // set lock init data
    lockConfig = UnlockEligibility.LockConfig({
      expirationDuration: 1 days, // 1 day
      tokenAddress: address(0), // ETH
      keyPrice: 1 ether, // 1 ETH
      maxNumberOfKeys: 10, // 10 keys
      lockManager: lockManager,
      version: 0, // default version
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
    deployInstance.prepare(false, address(implementation), targetHat, address(unlockFactory), saltNonce, lockConfig);
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

  function test_feeSplitPercentage() public view {
    assertEq(instance.FEE_SPLIT_PERCENTAGE(), feeSplitPercentage);
  }

  function test_feeSplitRecipient() public view {
    assertEq(instance.FEE_SPLIT_RECIPIENT(), feeSplitRecipient);
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
    if (lockConfig.version == 0) {
      assertEq(lock.publicLockVersion(), 14); // the default version
    } else {
      assertEq(lock.publicLockVersion(), lockConfig.version);
    }

    // lock price in module
    assertEq(instance.keyPrice(), lockConfig.keyPrice);
  }

  function test_createLockWithCustomVersion() public {
    lockConfig = UnlockEligibility.LockConfig({
      expirationDuration: 1 days, // 1 day
      tokenAddress: address(0), // ETH
      keyPrice: 1 ether, // 1 ETH
      maxNumberOfKeys: 10, // 10 keys
      lockManager: lockManager,
      version: 12, // custom version
      lockName: "Unlock Eligibility Test"
    });

    // deploy a new instance, using a new salt nonce to avoid collisions
    deployInstance.prepare(false, address(implementation), targetHat, address(unlockFactory), 2, lockConfig);
    instance = deployInstance.run();

    assertEq(instance.lock().publicLockVersion(), lockConfig.version);
  }
}

contract KeyPurchasePrice is WithInstanceTest {
  function test_keyPurchasePrice() public view {
    uint256 price = instance.keyPurchasePrice(address(0), address(0), address(0), bytes(""));
    assertEq(price, lockConfig.keyPrice);
  }
}

contract OnKeyPurchase is WithInstanceTest {
  function test_happy() public {
    IPublicLock lock = _getLock();

    // should revert because we're shortcutting the typical flow and calling this function without actually purchasing a
    // key, and so the wearer is not eligible and therefore cannot be minted the hat
    vm.expectRevert(HatsErrors.NotEligible.selector);

    vm.prank(address(lock));
    instance.onKeyPurchase(0, address(0), wearer, address(0), bytes(""), 0, 0);

    // the
    assertFalse(HATS.isWearerOfHat(wearer, targetHat));
  }

  function test_revert_notLock() public {
    vm.expectRevert(UnlockEligibility.NotLock.selector);
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
    vm.expectRevert();
    lock.transferFrom(wearer, nonWearer, tokenId);
  }
}
