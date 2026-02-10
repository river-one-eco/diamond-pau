// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ControllerInstance } from "../../../deploy/ControllerInstance.sol";

import {
    ForeignControllerDeploy,
    MainnetControllerDeploy
} from "../../../deploy/ControllerDeploy.sol";

import { IALMProxy } from "../../../src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../../../src/interfaces/IRateLimits.sol";

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";
import { RateLimits }        from "../../../src/RateLimits.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract ForeignController_Deploy_Tests is UnitTestBase {

    function test_deployController() external {
        address almProxy   = address(new ALMProxy(admin));
        address rateLimits = address(new RateLimits(admin));

        address controller = ForeignControllerDeploy.deployController(admin, almProxy, rateLimits);

        assertEq(ForeignController(controller).hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(ForeignController(controller).proxy(),      almProxy);
        assertEq(ForeignController(controller).rateLimits(), rateLimits);
    }

    function test_deployFull() external {
        ControllerInstance memory instance = ForeignControllerDeploy.deployFull(admin);

        assertEq(IALMProxy(instance.almProxy).hasRole(DEFAULT_ADMIN_ROLE, admin),           true);
        assertEq(IRateLimits(instance.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, admin),       true);
        assertEq(ForeignController(instance.controller).hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(ForeignController(instance.controller).proxy(),      instance.almProxy);
        assertEq(ForeignController(instance.controller).rateLimits(), instance.rateLimits);
    }

}

contract MainnetController_Deploy_Tests is UnitTestBase {

    function test_deployController() external {
        address almProxy   = address(new ALMProxy(admin));
        address rateLimits = address(new RateLimits(admin));

        address controller = MainnetControllerDeploy.deployController(admin, almProxy, rateLimits);

        assertEq(MainnetController(controller).hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(MainnetController(controller).proxy(),      almProxy);
        assertEq(MainnetController(controller).rateLimits(), rateLimits);
    }

    function test_deployFull() external {
        ControllerInstance memory instance = MainnetControllerDeploy.deployFull(admin);

        assertEq(IALMProxy(instance.almProxy).hasRole(DEFAULT_ADMIN_ROLE, admin),           true);
        assertEq(MainnetController(instance.controller).hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(IRateLimits(instance.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, admin),       true);

        assertEq(MainnetController(instance.controller).proxy(),      instance.almProxy);
        assertEq(MainnetController(instance.controller).rateLimits(), instance.rateLimits);
    }

}
