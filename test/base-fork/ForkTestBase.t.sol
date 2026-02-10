// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { ForeignControllerDeploy }       from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }            from "../../deploy/ControllerInstance.sol";
import { ForeignControllerInit as Init } from "../../deploy/ForeignControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

abstract contract ForkTestBase is Test {

    // TODO: Refactor to use live addresses

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant CONTROLLER_ROLE = keccak256("CONTROLLER");
    bytes32 internal constant FREEZER_ROLE    = keccak256("FREEZER");
    bytes32 internal constant RELAYER_ROLE    = keccak256("RELAYER");

    address internal constant FREEZER = Base.ALM_FREEZER_MULTISIG;
    address internal constant RELAYER = Base.ALM_RELAYER_MULTISIG;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    address payable internal almProxy;

    RateLimits        internal rateLimits;
    ForeignController internal foreignController;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        vm.createSelectFork(getChain('base').rpcUrl, _getBlock());

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull(Base.SPARK_EXECUTOR);

        almProxy          = payable(controllerInst.almProxy);
        rateLimits        = RateLimits(controllerInst.rateLimits);
        foreignController = ForeignController(controllerInst.controller);

        address[] memory relayers = new address[](1);
        relayers[0] = RELAYER;

        Init.ConfigAddressParams memory configAddresses = Init.ConfigAddressParams({
            freezer       : FREEZER,
            relayers      : relayers,
            oldController : address(0)
        });

        Init.CheckAddressParams memory checkAddresses = Init.CheckAddressParams({
            admin      : Base.SPARK_EXECUTOR,
            proxy      : almProxy,
            rateLimits : address(rateLimits)
        });

        vm.startPrank(Base.SPARK_EXECUTOR);

        Init.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 20782500;  // October 8, 2024
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _setControllerEntered() internal {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(address(foreignController));
    }

    function _assertReentrancyGuardWrittenToTwice(address controller) internal {
        ( , bytes32[] memory writeSlots ) = vm.accesses(controller);

        uint256 count = 0;

        for (uint256 i = 0; i < writeSlots.length; ++i) {
            if (writeSlots[i] != _REENTRANCY_GUARD_SLOT) continue;

            ++count;
        }

        assertEq(count, 2);
        assertEq(vm.load(controller, _REENTRANCY_GUARD_SLOT), _REENTRANCY_GUARD_NOT_ENTERED);
    }

}
