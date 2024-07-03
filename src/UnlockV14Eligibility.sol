// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // comment out before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { IPublicLock } from "../lib/unlock/smart-contracts/contracts/interfaces/IPublicLock.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { ILockKeyPurchaseHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyPurchaseHook.sol";
import { ILockKeyTransferHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyTransferHook.sol";

contract UnlockV14Eligibility is HatsEligibilityModule, ILockKeyPurchaseHook, ILockKeyTransferHook {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @dev Thrown when this contract is not aware of the Unlock factory for the current network
  error UnsupportedNetwork();

  /// @dev Thrown when a trying to transfer a key from the lock
  error NotTransferable();

  // @dev Thrown when the referrer fee is not the same in the lock as in this contract
  error InvalidReferrerFee();

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
    string lockName;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS 
  //////////////////////////////////////////////////////////////*/

  /// @notice The default version of the lock contract deploy along with an instance of this module
  uint16 public constant LOCK_VERSION = 14;

  /// @notice The address to split key purchase fees to, set as a referrer on the lock
  address public immutable REFERRER;

  /// @notice The percentage of key purchase fees that go to the referrer, in basis points (10000 = 100%)
  uint256 public immutable REFERRER_FEE_PERCENTAGE;

  /// @notice The Unlock Protocol factory contract
  /// @dev Used only for the implementation contract; for clones/instances, use {unlock}
  IUnlock public unlock_;

  /// @notice The Unlock Protocol factory contract
  function unlock() public view returns (IUnlock) {
    return UnlockV14Eligibility(IMPLEMENTATION()).unlock_();
  }

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
   * --------------------------------------------------------------------------+
   */

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The Unlock Protocol lock contract that is created along with this module and coupled to the hat
  IPublicLock public lock;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @param _version The version of the implementation contract
  /// @param _referrer The referrer address, which will receive a portion of the fees
  /// @param _referrerFeePercentage The percentage of fees to go to the referrer, in basis points (10000 = 100%)
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version, IUnlock _unlock, address _referrer, uint256 _referrerFeePercentage)
    HatsModule(_version)
  {
    unlock_ = _unlock;
    REFERRER = _referrer;
    REFERRER_FEE_PERCENTAGE = _referrerFeePercentage;
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZOR
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    LockConfig memory lockConfig = abi.decode(_initData, (LockConfig));

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
    lock = IPublicLock(unlock().createUpgradeableLockAtVersion(lockInitData, LOCK_VERSION));

    // set this contract as a hook for onKeyPurchase
    lock.setEventHooks({
      _onKeyPurchaseHook: address(this),
      _onKeyCancelHook: address(0),
      _onValidKeyHook: address(0),
      _onTokenURIHook: address(0),
      _onKeyTransferHook: address(this),
      _onKeyExtendHook: address(0),
      _onKeyGrantHook: address(0)
    });

    // set referrer fee
    lock.setReferrerFee(REFERRER, REFERRER_FEE_PERCENTAGE);

    // add lock manager role to the configured address
    lock.addLockManager(lockConfig.lockManager);
    // revokes itself lock manager
    lock.renounceLockManager();
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
    // Check if referrer fee is correct. Fail minting if incorrect.
    if (lock.referrerFees(REFERRER) != REFERRER_FEE_PERCENTAGE) {
      revert InvalidReferrerFee();
    }

    // Returns the lock's key price
    return lock.keyPrice();
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

  /// @inheritdoc ILockKeyTransferHook
  function onKeyTransfer(
    address, /* lockAddress */
    uint256, /* tokenId */
    address, /* operator */
    address, /* from */
    address, /* to */
    uint256 /* expirationTimestamp */
  ) external pure {
    revert NotTransferable();
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Reverts if a given address is not the {lock} contract
  function _checkIsLock(address _caller) internal view {
    if (_caller != address(lock)) revert NotLock();
  }
}
