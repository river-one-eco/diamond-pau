// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Avalanche } from "../../lib/grove-address-registry/src/Avalanche.sol";

import { ForeignControllerDeploy }       from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }            from "../../deploy/ControllerInstance.sol";
import { ForeignControllerInit as Init } from "../../deploy/ForeignControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

contract ForkTestBase is Test {

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

    address internal constant FREEZER = Avalanche.ALM_FREEZER;
    address internal constant RELAYER = Avalanche.ALM_RELAYER;

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
        vm.createSelectFork(getChain('avalanche').rpcUrl, _getBlock());

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull(Avalanche.GROVE_EXECUTOR);

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
            admin      : Avalanche.GROVE_EXECUTOR,
            proxy      : almProxy,
            rateLimits : address(rateLimits)
        });

        vm.startPrank(Avalanche.GROVE_EXECUTOR);

        Init.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 65896755;  // July 22, 2025
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
