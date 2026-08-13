// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ISparkVaultFacet }        from "../ISparkVaultFacet.sol";
import { IEnumerableIntegrations } from "../../../interfaces/IEnumerableIntegrations.sol";
import { makeAddressKey }          from "../../../libraries/RateLimitHelpers.sol";

import { SparkVaultFacet } from "../SparkVaultFacet.sol";

import { IntegrationTests } from "../../../../test/integration/IntegrationTests.t.sol";

interface IControllerLike {

    function getTakeRateLimitKey(address sparkVault) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract SparkVaultFacet_IntegrationTests is IntegrationTests {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new SparkVaultFacet());

        vm.label(facet, "SparkVaultFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getTakeRateLimitKey.selector,
            ISparkVaultFacet.getTakeRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("SPARK_VAULT_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "SPARK_VAULT_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getTakeRateLimitKey Tests                                                              ***/
    /**********************************************************************************************/

    function test_getTakeRateLimitKey() external {
        bytes32 keyPrefix   = keccak256("LIMIT_SPARK_VAULT_TAKE");
        address sparkVault  = makeAddr("sparkVault");

        assertEq(controller.getTakeRateLimitKey(sparkVault), makeAddressKey(keyPrefix, sparkVault));
    }

}
