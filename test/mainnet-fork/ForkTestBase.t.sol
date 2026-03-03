// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { Domain, DomainHelpers } from "../../lib/grove-xchain-helpers/src/testing/Domain.sol";

import { MainnetControllerDeploy }       from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }            from "../../deploy/ControllerInstance.sol";
import { MainnetControllerInit as Init } from "../../deploy/MainnetControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { MainnetController } from "../../src/MainnetController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

abstract contract ForkTestBase is Test {

    using DomainHelpers for *;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant FREEZER = Ethereum.ALM_FREEZER_MULTISIG; // TODO: ALL_CAPS_CONSTANTS
    address internal constant RELAYER = Ethereum.ALM_RELAYER_MULTISIG; // TODO: ALL_CAPS_CONSTANTS

    bytes32 internal constant CONTROLLER_ROLE = keccak256("CONTROLLER");
    bytes32 internal constant FREEZER_ROLE    = keccak256("FREEZER");
    bytes32 internal constant RELAYER_ROLE    = keccak256("RELAYER");

    address internal backstopRelayer = makeAddr("backstopRelayer");  // TODO: Replace with real backstop

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    address payable internal almProxy;

    RateLimits        internal rateLimits;
    MainnetController internal mainnetController;

    /**********************************************************************************************/
    /*** Bridging setup                                                                         ***/
    /**********************************************************************************************/

    Domain internal mainnet;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        mainnet = getChain("mainnet").createSelectFork(_getBlock());

        ControllerInstance memory controllerInst = MainnetControllerDeploy.deployFull(Ethereum.SPARK_PROXY);

        almProxy          = payable(controllerInst.almProxy);
        rateLimits        = RateLimits(controllerInst.rateLimits);
        mainnetController = MainnetController(controllerInst.controller);

        address[] memory relayers = new address[](1);
        relayers[0] = RELAYER;

        Init.ConfigAddressParams memory configAddresses = Init.ConfigAddressParams({
            freezer       : FREEZER,
            relayers      : relayers,
            oldController : address(0)
        });

        Init.CheckAddressParams memory checkAddresses = Init.CheckAddressParams({
            admin      : Ethereum.SPARK_PROXY,
            proxy      : almProxy,
            rateLimits : address(rateLimits)
        });

        vm.startPrank(Ethereum.SPARK_PROXY);

        Init.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        mainnetController.grantRole(RELAYER_ROLE, backstopRelayer);

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 20917850; //  October 7, 2024
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _setControllerEntered() internal virtual {
        vm.store(address(mainnetController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(address(mainnetController));
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
