// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { IPublicLock } from "../src/interfaces/IPublicLock.sol";

contract UnlockEligibility is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                            DATA MODELS
  //////////////////////////////////////////////////////////////*/

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
   * 72      | LOCK              | IPublicLock | 20      | {this}              |
   * --------------------------------------------------------------------------+
   */

  function LOCK() public pure returns (IPublicLock) {
    return IPublicLock(_getArgAddress(72));
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZOR
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
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

    eligible = LOCK().getHasValidKey(_wearer);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                            MODIFERS
  //////////////////////////////////////////////////////////////*/
}
