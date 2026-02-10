// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

import { MockPSM3 } from "../mocks/MockPSM3.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract MainnetController_Constructor_Tests is UnitTestBase {

    function test_constructor() public {
        MainnetController mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits")
        );

        assertEq(mainnetController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(mainnetController.proxy(),      makeAddr("almProxy"));
        assertEq(mainnetController.rateLimits(), makeAddr("rateLimits"));
    }

}

contract ForeignController_Constructor_Tests is UnitTestBase {

    function test_constructor() public {
        ForeignController foreignController = new ForeignController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits")
        );

        assertEq(foreignController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(foreignController.proxy(),      makeAddr("almProxy"));
        assertEq(foreignController.rateLimits(), makeAddr("rateLimits"));
    }

}
