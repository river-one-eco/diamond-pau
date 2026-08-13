// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IBasinFacet }             from "../IBasinFacet.sol";
import { IEnumerableIntegrations } from "../../../interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey }   from "../../../libraries/RateLimitHelpers.sol";

import { BasinFacet } from "../BasinFacet.sol";

import { IntegrationTests } from "../../../../test/integration/IntegrationTests.t.sol";

interface IControllerLike {

    function getDepositRateLimitKey(address basin, address asset) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address basin, address asset) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract BasinFacet_IntegrationTests is IntegrationTests {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new BasinFacet());

        vm.label(facet, "BasinFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IBasinFacet.getDepositRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IBasinFacet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("BASIN_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "BASIN_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_BASIN_DEPOSIT");
        address basin     = makeAddr("basin");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getDepositRateLimitKey(basin, asset),
            makeAddressAddressKey(keyPrefix, asset, basin)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_BASIN_WITHDRAW");
        address basin     = makeAddr("basin");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getWithdrawRateLimitKey(basin, asset),
            makeAddressAddressKey(keyPrefix, asset, basin)
        );
    }

}
