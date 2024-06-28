// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { IPublicLock, UnlockEligibility } from "../src/UnlockEligibility.sol";
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
  IHats public HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  HatsModuleFactory public factory;
  UnlockEligibility public instance;
  bytes public otherImmutableArgs;
  bytes public initArgs;
  uint256 public hatId;
  uint256 saltNonce;
  IPublicLock public lock;

  string public MODULE_VERSION;

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy implementation via the script
    prepare(false, MODULE_VERSION);
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

    // deploy the instance using the script
    DeployInstance deployInstance = new DeployInstance(true, address(implementation), hatId, address(lock), saltNonce);
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

  function test_lock() public view {
    assertEq(address(instance.LOCK()), address(lock));
  }
}

// TODO
contract UnitTests is WithInstanceTest { }
