// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // comment out before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { IPublicLock } from "../lib/unlock/smart-contracts/contracts/interfaces/IPublicLock.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { ILockKeyPurchaseHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyPurchaseHook.sol";
import { ILockKeyTransferHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyTransferHook.sol";

contract PublicLockV14Eligibility is HatsEligibilityModule, ILockKeyPurchaseHook, ILockKeyTransferHook {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @dev Thrown when this contract is not aware of the Unlock factory for the current network
  error UnsupportedNetwork();

  /// @dev Thrown when a trying to transfer a key from the lock
  error NotTransferable();

  /// @dev Thrown when the referrer fee is not the same in the lock as in this contract
  error InvalidReferrerFee();

  /// @dev Thrown when a lock-only function is called by an address that is not the lock contract
  error NotLock();

  /// @dev Thrown when the hat minting fails
  error HatMintFailed();

  /// @dev Thrown when a non-referrer calls a function only authorized to the referrer
  error NotReferrer();

  /*//////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when the referrer fee percentage is set in the implementation contract
  event ImplementationReferrerFeePercentageSet(uint256 referrerFeePercentage);

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS 
  //////////////////////////////////////////////////////////////*/

  /// @notice The default version of the lock contract deploy along with an instance of this module
  uint16 public constant LOCK_VERSION = 14;

  /// @notice The address to split key purchase fees to, set as a referrer on the lock
  address public immutable REFERRER;

  /// @notice The Unlock Protocol factory contract
  /// @dev Used only for the implementation contract; for clones/instances, use {unlock}
  IUnlock public unlock_;

  /// @notice The Unlock Protocol factory contract
  function unlock() public view returns (IUnlock) {
    return PublicLockV14Eligibility(IMPLEMENTATION()).unlock_();
  }

  /// @notice The referrer fee percentage for this module instance and associated lock. It is set to the value of the
  /// {implementationReferrerFeePercentage} during {setUp}, and cannot be updated.
  uint256 public referrerFeePercentage;

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

  /// @notice The referrer fee percentage that will be used for subsequent instances of this module.
  /// Will be 0 for all instances; use {referrerFeePercentage} for the fee percentage for a given instance.
  uint256 public implementationReferrerFeePercentage;

  /// @notice The Unlock Protocol lock contract that is created along with this module and coupled to the hat
  IPublicLock public lock;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @param _version The version of the implementation contract
  /// @param _referrer The referrer address, which will receive a portion of the fees
  /// @param __referrerFeePercentage The percentage of fees to go to the referrer, in basis points (10000 = 100%)
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version, IUnlock _unlock, address _referrer, uint256 __referrerFeePercentage)
    HatsModule(_version)
  {
    unlock_ = _unlock;
    REFERRER = _referrer;
    implementationReferrerFeePercentage = __referrerFeePercentage;
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    (
      uint256 _expirationDuration,
      address _tokenAddress,
      uint256 _keyPrice,
      uint256 _maxNumberOfKeys,
      address _lockManager,
      string memory _lockName
    ) = abi.decode(_initData, (uint256, address, uint256, uint256, address, string));

    // encode the lock init data
    bytes memory lockInitData = abi.encodeWithSignature(
      "initialize(address,uint256,address,uint256,uint256,string)",
      address(this),
      _expirationDuration,
      _tokenAddress,
      _keyPrice,
      _maxNumberOfKeys,
      _lockName
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

    // set referrer fee percentage in this instance
    uint256 fee = PublicLockV14Eligibility(IMPLEMENTATION()).implementationReferrerFeePercentage();
    referrerFeePercentage = fee;

    // set referrer and their fee percentage in the lock
    lock.setReferrerFee(REFERRER, fee);

    // add lock manager role to the configured address
    lock.addLockManager(_lockManager);
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
    if (lock.referrerFees(REFERRER) != referrerFeePercentage) {
      revert InvalidReferrerFee();
    }

    // Returns the lock's key price
    return lock.keyPrice();
  }

  /**
   * @inheritdoc ILockKeyPurchaseHook
   *
   * @notice Mints a hat whenever a key is purchased. If the recipient already has the hat, this function will
   * return without any action, allowing the key purchase to succeed. This logic exists in order to support migration to
   * a new lock without requiring hats to be revoked or renounced.
   *
   * There are two important notes:
   * 1. This contract must wear an admin hat of the {hatId} in order to be able to mint it.
   * 2. If the recipient is already wearing the {hatId}, the maxSupply of the hat must be higher than the current
   *    supply even though there will not be an additional hat minted. This is because, in the {HATS.mintHat} function,
   *    the maxSupply check occurs prior to the AlreadyWearingHat check. See the Hats Protocol code for details:
   *    https://github.com/Hats-Protocol/hats-protocol/blob/b4cdfbd964226d342afb1b0c8ebd92e0055f5b60/src/Hats.sol#L246-L247
   *
   * @dev Only callable by the {lock} contract
   */
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

    // try to mint the hat to the recipient
    (bool success, bytes memory returndata) =
      address(HATS()).call(abi.encodeWithSignature("mintHat(uint256,address)", hatId(), recipient));

    if (!success) {
      if (
        // if the mint fails because the recipient is already wearing the hat, do nothing and return
        keccak256(returndata)
          == keccak256(abi.encodeWithSignature("AlreadyWearingHat(address,uint256)", recipient, hatId()))
      ) {
        return;
      } else {
        // if the mint fails for any other reason, revert
        revert HatMintFailed();
      }
    }
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
                          ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the referrer fee percentage on the implementation contract. This value will be used for subsequent
   * instances of this module. It will not change the referrer fee percentage for existing instances.
   * @dev This function can only be called by the referrer.
   * @param _referrerFeePercentage The new referrer fee percentage
   */
  function setImplementationReferrerFeePercentage(uint256 _referrerFeePercentage) external {
    // caller must be the referrer
    if (msg.sender != REFERRER) revert NotReferrer();

    implementationReferrerFeePercentage = _referrerFeePercentage;

    emit ImplementationReferrerFeePercentageSet(_referrerFeePercentage);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Convenience function to get the key purchase token address from the lock
  function keyPurchaseToken() external view returns (address) {
    return lock.tokenAddress();
  }

  /// @notice Convenience function to get the expiration duration from the lock
  function expirationDuration() external view returns (uint256) {
    return lock.expirationDuration();
  }

  /// @notice Convenience function to get the max number of keys from the lock
  function maxNumberOfKeys() external view returns (uint256) {
    return lock.maxNumberOfKeys();
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Reverts if a given address is not the {lock} contract
  function _checkIsLock(address _caller) internal view {
    if (_caller != address(lock)) revert NotLock();
  }
}
