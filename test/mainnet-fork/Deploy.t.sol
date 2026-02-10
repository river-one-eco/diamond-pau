// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { MainnetControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import { IALMProxy }   from "../../src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../../src/interfaces/IRateLimits.sol";

import { MainnetController } from "../../src/MainnetController.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

contract MainnetController_Deploy_Tests is ForkTestBase {

    function test_deployFull() external {
        // Perform new deployments against existing fork environment

        ControllerInstance memory controllerInst = MainnetControllerDeploy.deployFull(Ethereum.SPARK_PROXY);

        assertEq(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY),   true);
        assertEq(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        assertEq(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY),   true);
        assertEq(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        _assertControllerInitState(controllerInst.controller, controllerInst.almProxy, controllerInst.rateLimits);
    }

    function test_deployController() external {
        // Perform new deployments against existing fork environment

        address newController = MainnetControllerDeploy.deployController(Ethereum.SPARK_PROXY, almProxy, address(rateLimits));

        _assertControllerInitState(newController, almProxy, address(rateLimits));
    }

    function _assertControllerInitState(address controller, address almProxy, address rateLimits)
        internal
        view
    {
        assertEq(MainnetController(controller).hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY), true);
        assertEq(MainnetController(controller).hasRole(DEFAULT_ADMIN_ROLE, address(this)),        false); // Deployer never gets admin

        assertEq(MainnetController(controller).proxy(),      almProxy);
        assertEq(MainnetController(controller).rateLimits(), rateLimits);
    }

}
