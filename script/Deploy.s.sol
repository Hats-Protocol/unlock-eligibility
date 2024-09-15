// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsModuleFactory } from "../lib/hats-module/src/HatsModuleFactory.sol";
import { IUnlock, PublicLockV14Eligibility } from "../src/PublicLockV14Eligibility.sol";

contract Deploy is Script {
  PublicLockV14Eligibility public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x4a75));

  // default values
  bool internal _verbose = true;
  string internal _version = "0.1.2"; // increment this with each new deployment
  address internal _feeSplitRecipient = 0x58C8854a8E51BdCE9F00726B966905FE2719B4D9;
  uint256 internal _feeSplitPercentage = 500; // 5%

  /// @dev Override default values, if desired
  function prepare(bool verbose, string memory version, address feeSplitRecipient, uint256 feeSplitPercentage) public {
    _verbose = verbose;
    _version = version;
    _feeSplitRecipient = feeSplitRecipient;
    _feeSplitPercentage = feeSplitPercentage;
  }

  function getDeploymentDataForNetwork(uint256 _chainId) public view returns (bytes memory) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/script/Deployments.json");
    string memory json = vm.readFile(path);
    string memory chain = string.concat(".", vm.toString(_chainId));
    return vm.parseJson(json, chain);
  }

  function getDeploymentData() public view returns (bytes memory) {
    return getDeploymentDataForNetwork(block.chainid);
  }

  function getUnlockAddress() public view returns (IUnlock) {
    bytes memory params = getDeploymentData();

    // json is parsed in alphabetical order by key
    (, address unlock,) = abi.decode(params, (uint256, address, uint256));

    return IUnlock(unlock);
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
    implementation =
      new PublicLockV14Eligibility{ salt: SALT }(_version, _feeSplitRecipient, _feeSplitPercentage, deployer());

    // set the unlock address on the implementation
    implementation.setUnlock(getUnlockAddress());

    vm.stopBroadcast();

    _log("");
  }
}

contract DeployInstance is Script {
  HatsModuleFactory public factory = HatsModuleFactory(0x0a3f85fa597B6a967271286aA0724811acDF5CD9);
  PublicLockV14Eligibility public instance;

  // default values
  bool internal _verbose = true;
  address internal _implementation = 0x13d7ca8F08CDCb248df0792bcC5989509CE119E0; // test3
  uint256 internal _saltNonce = 2;
  uint256 internal _hatId = 0x0000020f00010001000000000000000000000000000000000000000000000000;
  address internal _unlockFactory = 0x36b34e10295cCE69B652eEB5a8046041074515Da; // sepolia

  // lock config defaults
  uint256 internal _expirationDuration = 30 days;
  address internal _tokenAddress = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC
  uint256 internal _keyPrice = 1_000_000; // 1 USDC
  uint256 internal _maxNumberOfKeys = 10_000;
  address internal _lockManager = 0x843a3c4ED93fb1f1335D5d174745551468106715;
  string internal _lockName = "Subscription Module test3 instance 1";

  /// @dev Override default values, if desired
  function prepare(
    bool verbose,
    address implementation,
    uint256 hatId,
    uint256 saltNonce,
    uint256 expirationDuration,
    address tokenAddress,
    uint256 keyPrice,
    uint256 maxNumberOfKeys,
    address lockManager,
    string memory lockName
  ) public {
    _verbose = verbose;
    _implementation = implementation;
    _hatId = hatId;
    _saltNonce = saltNonce;
    _expirationDuration = expirationDuration;
    _tokenAddress = tokenAddress;
    _keyPrice = keyPrice;
    _maxNumberOfKeys = maxNumberOfKeys;
    _lockManager = lockManager;
    _lockName = lockName;
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
  function run() public virtual returns (PublicLockV14Eligibility) {
    vm.startBroadcast(deployer());

    instance = PublicLockV14Eligibility(
      factory.createHatsModule(
        _implementation,
        _hatId,
        abi.encodePacked(), // other immutable args
        abi.encode(_expirationDuration, _tokenAddress, _keyPrice, _maxNumberOfKeys, _lockManager, _lockName), // init
          // data
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
forge script script/Deploy.s.sol -f sepolia

## B. Deploy to real network and verify on etherscan
forge script script/Deploy.s.sol -f mainnet --broadcast --verify

## C. Fix verification issues (replace values in curly braces with the actual values)
forge verify-contract --chain-id 11155111 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode \
"constructor(string,address,address,uint256)" "0.1.0" 0x36b34e10295cCE69B652eEB5a8046041074515Da \
0x58C8854a8E51BdCE9F00726B966905FE2719B4D9 500 ) --compiler-version v0.8.26 \
0xA235F37A5e98980Ee439deB0600F06d956707D61 \
 src/PublicLockV14Eligibility.sol:PublicLockV14Eligibility --etherscan-api-key $ETHERSCAN_KEY

## D. To verify ir-optimized contracts on etherscan...
  1. Run (C) with the following additional flag: `--show-standard-json-input > etherscan.json`
  2. Patch `etherscan.json`: `"optimizer":{"enabled":true,"runs":100}` =>
`"optimizer":{"enabled":true,"runs":100},"viaIR":true`
  3. Upload the patched `etherscan.json` to etherscan manually

  See this github issue for more: https://github.com/foundry-rs/foundry/issues/3507#issuecomment-1465382107
*/
