// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsModuleFactory } from "../lib/hats-module/src/HatsModuleFactory.sol";
import { UnlockEligibility } from "../src/UnlockEligibility.sol";

contract Deploy is Script {
  UnlockEligibility public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x4a75));

  // default values
  bool internal _verbose = true;
  string internal _version = "test1"; // increment this with each new deployment
  address internal _feeSplitRecipient = 0x018e494352a3E68e16d03ed976Fd64134bd82E72;
  uint256 internal _feeSplitPercentage = 1000; // 10%

  /// @dev Override default values, if desired
  function prepare(bool verbose, string memory version, address feeSplitRecipient, uint256 feeSplitPercentage) public {
    _verbose = verbose;
    _version = version;
    _feeSplitRecipient = feeSplitRecipient;
    _feeSplitPercentage = feeSplitPercentage;
  }

  /// @dev Set up the deployer via their private key from the environment
  function deployer() public returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  function _log(string memory prefix) internal view {
    if (_verbose) {
      console2.log(string.concat(prefix, "Module:"), address(implementation));
    }
  }

  /// @dev Deploy the contract to a deterministic address via forge's create2 deployer factory.
  function run() public virtual {
    vm.startBroadcast(deployer());

    /**
     * @dev Deploy the contract to a deterministic address via forge's create2 deployer factory, which is at this
     * address on all chains: `0x4e59b44847b379578588920cA78FbF26c0B4956C`.
     * The resulting deployment address is determined by only two factors:
     *    1. The bytecode hash of the contract to deploy. Setting `bytecode_hash` to "none" in foundry.toml ensures that
     *       never differs regardless of where its being compiled
     *    2. The provided salt, `SALT`
     */
    implementation = new UnlockEligibility{ salt: SALT }(_version, _feeSplitRecipient, _feeSplitPercentage);

    vm.stopBroadcast();

    _log("");
  }
}

contract DeployInstance is Script {
  HatsModuleFactory public factory = HatsModuleFactory(0x0a3f85fa597B6a967271286aA0724811acDF5CD9);
  UnlockEligibility public instance;

  // default values
  bool internal _verbose = true;
  address internal _implementation = 0xBDE01a70419856bfCe2fC7B87f147577F67D593a; // test1
  uint256 internal _saltNonce = 1;
  uint256 internal _hatId = 0x0000001f00010001000000000000000000000000000000000000000000000000;
  address internal _unlockFactory = 0x36b34e10295cCE69B652eEB5a8046041074515Da; // sepolia
  UnlockEligibility.LockConfig internal _lockConfig;

  // lock config defaults
  uint256 internal _expirationDuration = 7 days;
  address internal _tokenAddress = 0x0000000000000000000000000000000000000000; // ETH
  uint256 internal _keyPrice = 0.0001 ether;
  uint256 internal _maxNumberOfKeys = 10_000;
  address internal _lockManager = 0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4;
  uint16 internal _version = 0; // will default to 14
  string internal _lockName = "Hat Lock Test 1";

  /// @dev Override default values, if desired
  function prepare(
    bool verbose,
    address implementation,
    uint256 hatId,
    address unlockFactory,
    uint256 saltNonce,
    UnlockEligibility.LockConfig memory lockConfig
  ) public {
    _verbose = verbose;
    _implementation = implementation;
    _hatId = hatId;
    _unlockFactory = unlockFactory;
    _saltNonce = saltNonce;
    _lockConfig = lockConfig;
  }

  /// @dev Set up the deployer via their private key from the environment
  function deployer() public returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  function _log(string memory prefix) internal view {
    if (_verbose) {
      console2.log(string.concat(prefix, "Instance:"), address(instance));
      console2.log(string.concat("Lock"), address(instance.lock()));
    }
  }

  /// @dev Deploy the contract to a deterministic address via forge's create2 deployer factory.
  function run() public virtual returns (UnlockEligibility) {
    vm.startBroadcast(deployer());

    // use the default values if the prepared lockConfig is empty
    if (_lockConfig.expirationDuration == 0) {
      _lockConfig.expirationDuration = _expirationDuration;
      _lockConfig.keyPrice = _keyPrice;
      _lockConfig.maxNumberOfKeys = _maxNumberOfKeys;
      _lockConfig.lockManager = _lockManager;
      _lockConfig.version = _version;
      _lockConfig.lockName = _lockName;
    }

    instance = UnlockEligibility(
      factory.createHatsModule(
        _implementation,
        _hatId,
        abi.encodePacked(_unlockFactory), // other immutable args
        abi.encode(_lockConfig), // init data
        _saltNonce
      )
    );

    vm.stopBroadcast();

    _log("");

    return instance;
  }
}

/* FORGE CLI COMMANDS

## A. Simulate the deployment locally
forge script script/Deploy.s.sol -f mainnet

## B. Deploy to real network and verify on etherscan
forge script script/Deploy.s.sol -f mainnet --broadcast --verify

## C. Fix verification issues (replace values in curly braces with the actual values)
forge verify-contract --chain-id 1 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode \
 "constructor({args})" "{arg1}" "{arg2}" "{argN}" ) \ 
 --compiler-version v0.8.19 {deploymentAddress} \
 src/{Counter}.sol:{Counter} --etherscan-api-key $ETHERSCAN_KEY

## D. To verify ir-optimized contracts on etherscan...
  1. Run (C) with the following additional flag: `--show-standard-json-input > etherscan.json`
  2. Patch `etherscan.json`: `"optimizer":{"enabled":true,"runs":100}` =>
`"optimizer":{"enabled":true,"runs":100},"viaIR":true`
  3. Upload the patched `etherscan.json` to etherscan manually

  See this github issue for more: https://github.com/foundry-rs/foundry/issues/3507#issuecomment-1465382107

*/
