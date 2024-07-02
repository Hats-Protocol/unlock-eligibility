// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // comment out before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { IPublicLock } from "../lib/unlock/smart-contracts/contracts/interfaces/IPublicLock.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { ILockKeyPurchaseHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyPurchaseHook.sol";

contract UnlockEligibility is HatsEligibilityModule, ILockKeyPurchaseHook {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @dev Thrown when this contract is not aware of the Unlock factory for the current network
  error UnsupportedNetwork();

  /// @dev Thrown when a lock-only function is called by an address that is not the lock contract
  error NotLock();

  /*//////////////////////////////////////////////////////////////
                            DATA MODELS
  //////////////////////////////////////////////////////////////*/

  struct LockConfig {
    uint256 expirationDuration;
    address tokenAddress;
    uint256 keyPrice;
    uint256 maxNumberOfKeys;
    address lockManager;
    uint16 version;
    string lockName;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS 
  //////////////////////////////////////////////////////////////*/

  /// @notice The default version of the lock contract deploy along with an instance of this module
  uint16 public constant DEFAULT_LOCK_VERSION = 14;

  /// @notice The address to split key purchase fees to
  address public immutable FEE_SPLIT_RECIPIENT;

  /// @notice The percentage of key purchase fees to split, in basis points (10000 = 100%)
  uint256 public immutable FEE_SPLIT_PERCENTAGE;

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their location.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * --------------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                                 |
   * --------------------------------------------------------------------------|
   * Offset  | Constant          | Type        | Length  | Source              |
   * --------------------------------------------------------------------------|
   * 0       | IMPLEMENTATION    | address     | 20      | HatsModule          |
   * 20      | HATS              | address     | 20      | HatsModule          |
   * 40      | hatId             | uint256     | 32      | HatsModule          |
   * 72      | UNLOCK            | address     | 20      | {this}              |
   * --------------------------------------------------------------------------+
   */

  /// @dev The configured Unlock factory contract address. Overrides the default address for each chain as set in
  /// {getUnlockContract}.
  function _UNLOCK() internal pure returns (address) {
    return (_getArgAddress(72));
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The Unlock Protocol lock contract that is created along with this module and coupled to the hat
  IPublicLock public lock;

  /// @notice The price of a key for the lock
  /// @dev Stored here to facilitate the {keyPurchasePrice} hook
  uint256 public keyPrice;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @param _version The version of the implementation contract
  /// @param _feeSplitRecipient The address to split fees to
  /// @param _feeSplitPercentage The percentage of fees to split, in basis points (10000 = 100%)
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version, address _feeSplitRecipient, uint256 _feeSplitPercentage) HatsModule(_version) {
    FEE_SPLIT_RECIPIENT = _feeSplitRecipient;
    FEE_SPLIT_PERCENTAGE = _feeSplitPercentage;
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZOR
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    LockConfig memory lockConfig = abi.decode(_initData, (LockConfig));

    // determine the lock version to use, falling back to the default version if the given version is 0
    uint16 version_ = lockConfig.version == 0 ? DEFAULT_LOCK_VERSION : lockConfig.version;

    // encode the lock init data
    bytes memory lockInitData = abi.encodeWithSignature(
      "initialize(address,uint256,address,uint256,uint256,string)",
      address(this),
      lockConfig.expirationDuration,
      lockConfig.tokenAddress,
      lockConfig.keyPrice,
      lockConfig.maxNumberOfKeys,
      lockConfig.lockName
    );

    // create the new lock
    lock = IPublicLock(getUnlockContract().createUpgradeableLockAtVersion(lockInitData, version_));

    // set this contract as a hook for onKeyPurchase
    lock.setEventHooks({
      _onKeyPurchaseHook: address(this),
      _onKeyCancelHook: address(0),
      _onValidKeyHook: address(0),
      _onTokenURIHook: address(0),
      _onKeyTransferHook: address(0),
      _onKeyExtendHook: address(0),
      _onKeyGrantHook: address(0)
    });

    // set referrer fee
    lock.setReferrerFee(FEE_SPLIT_RECIPIENT, FEE_SPLIT_PERCENTAGE);

    // transfer lock manager role to the configured address
    // QUESTION is the the right approach?
    lock.addLockManager(lockConfig.lockManager);
    lock.renounceLockManager();

    // store the key price for retrieval by the {keyPurchasePrice} hook
    keyPrice = lockConfig.keyPrice;
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    // This module does not deal with standing, so we default to good standing (true)
    standing = true;

    eligible = lock.getHasValidKey(_wearer);
  }

  /*//////////////////////////////////////////////////////////////
                        UNLOCK HOOK FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ILockKeyPurchaseHook
  function keyPurchasePrice(
    address, /* from */
    address, /* recipient */
    address, /* referrer */
    bytes calldata /* data */
  ) external view returns (uint256 minKeyPrice) {
    minKeyPrice = keyPrice;
  }

  /// @inheritdoc ILockKeyPurchaseHook
  function onKeyPurchase(
    uint256, /* tokenId */
    address, /* from */
    address recipient,
    address, /* referrer */
    bytes calldata, /* data */
    uint256, /* minKeyPrice */
    uint256 /* pricePaid */
  ) external {
    // caller must be the lock contract
    _checkIsLock(msg.sender);

    /// @dev Will revert if this contract is not an admin of the hat
    HATS().mintHat(hatId(), recipient);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Gets the address of the Unlock factory contract, falling back to hardcoded defaults for each
  /// EVM-equivalent network supported by Unlock Protocol:
  /// https://docs.unlock-protocol.com/core-protocol/unlock/networks
  /// @dev This facilitates lazy configuration for supported networks, while also retaining configuration flexibility.
  function getUnlockContract() public view returns (IUnlock) {
    if (_UNLOCK() > address(0)) {
      return IUnlock(_UNLOCK());
    } else {
      // return the address of the factory based on the chainid
      if (block.chainid == 1) return IUnlock(0xe79B93f8E22676774F2A8dAd469175ebd00029FA); // ethereum
      if (block.chainid == 11_155_111) return IUnlock(0x36b34e10295cCE69B652eEB5a8046041074515Da); // sepolia
      if (block.chainid == 10) return IUnlock(0x99b1348a9129ac49c6de7F11245773dE2f51fB0c); // optimism
      if (block.chainid == 42_161) return IUnlock(0x1FF7e338d5E582138C46044dc238543Ce555C963); // arbitrum
      if (block.chainid == 8453) return IUnlock(0xd0b14797b9D08493392865647384974470202A78); // base
      if (block.chainid == 84_532) return IUnlock(0x259813B665C8f6074391028ef782e27B65840d89); // base sepolia
      if (block.chainid == 137) return IUnlock(0xE8E5cd156f89F7bdB267EabD5C43Af3d5AF2A78f); // polygon
      if (block.chainid == 42_220) return IUnlock(0x1FF7e338d5E582138C46044dc238543Ce555C963); // celo
      if (block.chainid == 100) return IUnlock(0x1bc53f4303c711cc693F6Ec3477B83703DcB317f); // gnosis
      if (block.chainid == 59_144) return IUnlock(0x70B3c9Dd9788570FAAb24B92c3a57d99f8186Cc7); // linea
      if (block.chainid == 534_352) return IUnlock(0x259813B665C8f6074391028ef782e27B65840d89); // scroll

      else revert UnsupportedNetwork();
    }
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Reverts if a given address is not the {lock} contract
  function _checkIsLock(address _caller) internal view {
    if (_caller != address(lock)) revert NotLock();
  }
}
