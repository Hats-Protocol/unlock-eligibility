// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // comment out before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { IPublicLock } from "../lib/unlock/smart-contracts/contracts/interfaces/IPublicLock.sol";
import { IUnlock } from "../lib/unlock/smart-contracts/contracts/interfaces/IUnlock.sol";
import { ILockKeyPurchaseHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyPurchaseHook.sol";
import { ILockKeyTransferHook } from "../lib/unlock/smart-contracts/contracts/interfaces/hooks/ILockKeyTransferHook.sol";

contract UnlockEligibility is HatsEligibilityModule, ILockKeyPurchaseHook, ILockKeyTransferHook {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  error UnsupportedNetwork();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

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
  function _UNLOCK() internal pure returns (address) {
    return (_getArgAddress(72));
  }

  address public immutable FEE_SPLIT_RECIPIENT;
  uint256 public immutable FEE_SPLIT_PERCENTAGE; // in basis points (10000 = 100%)

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  IPublicLock public lock;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version, address _feeSplitRecipient, uint256 _feeSplitPercentage) HatsModule(_version) {
    FEE_SPLIT_RECIPIENT = _feeSplitRecipient;
    FEE_SPLIT_PERCENTAGE = _feeSplitPercentage;
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZOR
  //////////////////////////////////////////////////////////////*/

  /*
    SPEC for the full flow

    0. decode lock contract config from _initData ✅
    1. encode lock init data with `initialize` signature ✅
    2. create the lock contract with the config ✅
    3. store the lock address ✅
    4. set this contract as an onPurchase and onTransfer hook for the lock — setEventHooks() ✅
    5. set referrer fee ✅
    6. add lock manager role to the configured address ✅
    7. revokes itself as a lock manager ✅
    
  */

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    LockConfig memory lockConfig = abi.decode(_initData, (LockConfig));

    // determine the lock version to use, defaulting to 14
    uint16 version_ = lockConfig.version == 0 ? 14 : lockConfig.version;

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

    // set this contract as a hook for keyPurchase and keyTransfer
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
    lock.setReferrerFee(FEE_SPLIT_RECIPIENT, FEE_SPLIT_PERCENTAGE);

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
  function keyPurchasePrice(address from, address recipient, address referrer, bytes calldata data)
    external
    view
    returns (uint256 minKeyPrice)
  {
    // Returns the lock's key price (unless we want to have a custom price for specific hat wearerrs)
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
    /// @dev Will revert if this contract is not an admin of the hat
    HATS().mintHat(hatId(), recipient);
  }

  /// @inheritdoc ILockKeyTransferHook
  function onKeyTransfer(
    address, /* lockAddress */
    uint256, /* tokenId */
    address, /* operator */
    address from,
    address to,
    uint256 /* expirationTimestamp */
  ) external {
    /// @dev We use the revoke & mint approach here rather than transfer in case the hat is immutable

    // Revoke the hat from the from address (current wearer) without putting them in bad standing
    /// @dev Will revert if this contract is the hat's eligibility module
    HATS().setHatWearerStatus(hatId(), from, false, true);

    // Mint the hat to the to address (new wearer)
    // Since the key has already been transferred, the new wearer is eligible and so minting will succeed
    /// @dev Will revert if this contract is not an admin of the hat
    HATS().mintHat(hatId(), to);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @notice Gets the address of the Unlock factory contract, falling back to hardcoded defaults for a specific set of
  /// networks. This facilitates lazy configuration for supported networks, while also retaining configuration
  /// flexibility.
  /// @dev https://docs.unlock-protocol.com/core-protocol/unlock/networks
  function getUnlockContract() public view returns (IUnlock) {
    if (_UNLOCK() > address(0)) {
      return IUnlock(_UNLOCK());
    } else {
      // return the address of the factory based on the chainid
      if (block.chainid == 1) return IUnlock(0xe79B93f8E22676774F2A8dAd469175ebd00029FA);
      // TODO add other networks
      else revert UnsupportedNetwork();
    }
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                            MODIFERS
  //////////////////////////////////////////////////////////////*/
}
