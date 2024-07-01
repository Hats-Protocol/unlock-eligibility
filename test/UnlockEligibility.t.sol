// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { IPublicLock, UnlockEligibility } from "../src/UnlockEligibility.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { HatsModuleFactory, IHats } from "hats-module/utils/DeployFunctions.sol";
import { Deploy, DeployInstance } from "../script/Deploy.s.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

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
  uint256 public hatId;
  uint256 saltNonce;

  DeployInstance public deployInstance;

  IUnlock public unlockFactory = IUnlock(0xe79B93f8E22676774F2A8dAd469175ebd00029FA); // UnlockFactory on mainnet
  IPublicLock public lock;

  address public feeSplitRecipient = makeAddr("fee split recipient");
  uint256 public feeSplitPercentage = 1000; // 10%
  address public lockManager = makeAddr("lock manager");

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

    // set up the Unlock lock
    lock = IPublicLock(makeAddr("Unlock lock")); // TODO

    // set the salt nonce
    saltNonce = 1;

    // set the test hat
    hatId = 10;

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

    // deploy the instance using the script
    deployInstance =
      new DeployInstance(false, address(implementation), hatId, address(unlockFactory), saltNonce, lockConfig);
    instance = deployInstance.run();
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
    assertEq(instance.hatId(), hatId);
  }

  function test_feeSplitPercentage() public view {
    assertEq(instance.FEE_SPLIT_PERCENTAGE(), feeSplitPercentage);
  }

  function test_feeSplitRecipient() public view {
    assertEq(instance.FEE_SPLIT_RECIPIENT(), feeSplitRecipient);
  }

  function test_createLock() public view {
    IPublicLock lock = IPublicLock(instance.lock());
    assertTrue(lock.isLockManager(address(lockManager)));
    assertFalse(lock.isLockManager(address(instance)));
    assertEq(lock.keyPrice(), lockConfig.keyPrice);
    assertEq(lock.maxNumberOfKeys(), lockConfig.maxNumberOfKeys);
    assertEq(lock.expirationDuration(), lockConfig.expirationDuration);
    assertEq(lock.name(), lockConfig.lockName);
    assertEq(lock.tokenAddress(), lockConfig.tokenAddress);

    assertEq(lock.onKeyPurchaseHook(), address(instance));
    assertEq(lock.onKeyTransferHook(), address(instance));

    if (lockConfig.version == 0) {
      assertEq(lock.publicLockVersion(), 14); // the default version
    } else {
      assertEq(lock.publicLockVersion(), lockConfig.version);
    }
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
    deployInstance.prepare(false, address(implementation), hatId, address(unlockFactory), 2, lockConfig);
    instance = deployInstance.run();

    assertEq(instance.lock().publicLockVersion(), lockConfig.version);
  }
}

// TODO
contract UnitTests is WithInstanceTest { }
