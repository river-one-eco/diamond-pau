// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import { IALMProxy }   from "../../src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../../src/interfaces/IRateLimits.sol";

import { ForeignController } from "../../src/ForeignController.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

contract ForeignController_Deploy_Tests is ForkTestBase {

    function test_deployFull() external {
        // Perform new deployments against existing fork environment

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull(Base.SPARK_EXECUTOR);

        assertEq(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        assertEq(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        _assertControllerInitState(controllerInst.controller, controllerInst.almProxy, controllerInst.rateLimits);
    }

    function test_deployController() external {
        // Perform new deployments against existing fork environment

        address newController = ForeignControllerDeploy.deployController(Base.SPARK_EXECUTOR, almProxy, address(rateLimits));

        _assertControllerInitState(newController, almProxy, address(rateLimits));
    }

    function _assertControllerInitState(address controller, address almProxy, address rateLimits)
        internal
        view
    {
        assertEq(ForeignController(controller).hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(ForeignController(controller).hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        assertEq(ForeignController(controller).proxy(),      almProxy);
        assertEq(ForeignController(controller).rateLimits(), rateLimits);
    }

}
