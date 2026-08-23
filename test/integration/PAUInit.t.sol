// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

import { PAUInit, PAUInstance } from "../../deploy/PAUInit.sol";

interface IAccessControlLike {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IALMProxyLike {
    function CONTROLLER() external view returns (bytes32);
}

interface IRateLimitsLike {
    function CONTROLLER() external view returns (bytes32);
}

/**
 * @notice Governance-proxy stand-in (PauseProxy / SubProxy) executing a spell action. PAUInit is
 *         internal-functions-only, so it inlines here and executes with this contract as
 *         `msg.sender` / `address(this)` — as it would in a delegatecalled spell. Deployed as the
 *         sole DEFAULT_ADMIN_ROLE holder on every component.
 */
contract GovernanceHarness {

    function initPAU(PAUInstance memory inst, bytes32[] memory integrationIds) external {
        PAUInit.init(inst, integrationIds);
    }

    function addAllocator(PAUInstance memory inst, address agent) external {
        PAUInit.addAllocator(inst, agent);
    }

}

contract PAUInit_Integration_Tests is Test {

    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    GovernanceHarness internal governance;

    Beacon     internal beacon;
    PAUFactory internal factory;

    function setUp() external {
        governance = new GovernanceHarness();
        beacon     = new Beacon(makeAddr("beaconAdmin"));
        factory    = new PAUFactory(address(beacon));
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    // Deploy a fresh stack owned solely by `admin`, WITHOUT the CONTROLLER grants — granting those
    // is exactly what PAUInit.init performs.
    function _deployStack(address admin) internal returns (PAUInstance memory inst) {
        inst.accessControls = factory.deployAccessControls(admin);
        inst.almProxy       = factory.deployALMProxy(admin);
        inst.rateLimits     = factory.deployRateLimits(admin);
        inst.controller     =
            factory.deployController(inst.accessControls, inst.almProxy, inst.rateLimits);
        inst.beacon         = address(beacon);
    }

    function _controllerRoleGranted(address component, address controller)
        internal
        view
        returns (bool)
    {
        return IAccessControlLike(component).hasRole(
            IALMProxyLike(component).CONTROLLER(),
            controller
        );
    }

    /**********************************************************************************************/
    /*** Init Tests                                                                             ***/
    /**********************************************************************************************/

    function test_init_wiresControllerRoles() external {
        PAUInstance memory inst = _deployStack(address(governance));

        // Precondition: the Controller holds no CONTROLLER role yet.
        assertFalse(_controllerRoleGranted(inst.almProxy,   inst.controller));
        assertFalse(_controllerRoleGranted(inst.rateLimits, inst.controller));

        governance.initPAU(inst, new bytes32[](0));

        assertTrue(_controllerRoleGranted(inst.almProxy,   inst.controller));
        assertTrue(_controllerRoleGranted(inst.rateLimits, inst.controller));
    }

    function test_init_emptyIntegrationIds_skipsUpdate() external {
        PAUInstance memory inst = _deployStack(address(governance));

        // Empty array must not revert (the Controller reverts on an empty updateIntegrations).
        governance.initPAU(inst, new bytes32[](0));

        assertTrue(_controllerRoleGranted(inst.almProxy, inst.controller));
    }

    function test_init_mismatchedAccessControls_reverts() external {
        PAUInstance memory inst = _deployStack(address(governance));
        inst.accessControls = makeAddr("wrong");

        vm.expectRevert(bytes("PAUInit/controller-access-controls-mismatch"));
        governance.initPAU(inst, new bytes32[](0));
    }

    function test_init_mismatchedProxy_reverts() external {
        PAUInstance memory inst = _deployStack(address(governance));
        inst.almProxy = makeAddr("wrong");

        vm.expectRevert(bytes("PAUInit/controller-proxy-mismatch"));
        governance.initPAU(inst, new bytes32[](0));
    }

    function test_init_mismatchedBeacon_reverts() external {
        PAUInstance memory inst = _deployStack(address(governance));
        inst.beacon = makeAddr("wrong");

        vm.expectRevert(bytes("PAUInit/controller-beacon-mismatch"));
        governance.initPAU(inst, new bytes32[](0));
    }

    function test_init_mismatchedRateLimits_reverts() external {
        PAUInstance memory inst = _deployStack(address(governance));
        inst.rateLimits = makeAddr("wrong");

        vm.expectRevert(bytes("PAUInit/controller-rate-limits-mismatch"));
        governance.initPAU(inst, new bytes32[](0));
    }

    function test_init_notAdmin_reverts() external {
        // Stack owned by someone else: the harness holds no admin anywhere.
        PAUInstance memory inst = _deployStack(makeAddr("otherAdmin"));

        vm.expectRevert(bytes("PAUInit/not-access-controls-admin"));
        governance.initPAU(inst, new bytes32[](0));
    }

    /**********************************************************************************************/
    /*** Allocator Tests                                                                        ***/
    /**********************************************************************************************/

    function test_addAllocator_grantsAllocatorRole() external {
        PAUInstance memory inst = _deployStack(address(governance));

        address agent = makeAddr("agent");

        assertFalse(IAccessControlLike(inst.accessControls).hasRole(ALLOCATOR_ROLE, agent));

        governance.addAllocator(inst, agent);

        assertTrue(IAccessControlLike(inst.accessControls).hasRole(ALLOCATOR_ROLE, agent));
    }

    function test_addAllocator_zeroAgent_reverts() external {
        PAUInstance memory inst = _deployStack(address(governance));

        vm.expectRevert(bytes("PAUInit/agent-zero-address"));
        governance.addAllocator(inst, address(0));
    }

}
