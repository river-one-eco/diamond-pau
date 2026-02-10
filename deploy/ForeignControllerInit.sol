// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ForeignController } from "../src/ForeignController.sol";

import { IALMProxy }   from "../src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../src/interfaces/IRateLimits.sol";

import { ControllerInstance } from "./ControllerInstance.sol";

library ForeignControllerInit {

    /**********************************************************************************************/
    /*** Structs and constants                                                                  ***/
    /**********************************************************************************************/

    struct CheckAddressParams {
        address admin;
        address proxy;
        address rateLimits;
    }

    struct ConfigAddressParams {
        address   freezer;
        address[] relayers;
        address   oldController; // TODO: Remove this field
    }

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    /**********************************************************************************************/
    /*** Internal library functions                                                             ***/
    /**********************************************************************************************/

    function initAlmSystem(
        ControllerInstance  memory controllerInst,
        ConfigAddressParams memory configAddresses,
        CheckAddressParams  memory checkAddresses
    )
        internal
    {
        // Step 1: Do sanity checks outside of the controller

        require(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, checkAddresses.admin),     "ForeignControllerInit/incorrect-admin-almProxy");
        require(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, checkAddresses.admin), "ForeignControllerInit/incorrect-admin-rateLimits");

        // Step 2: Initialize the controller

        _initController(controllerInst, configAddresses, checkAddresses);
    }

    function upgradeController(
        ControllerInstance  memory controllerInst,
        ConfigAddressParams memory configAddresses,
        CheckAddressParams  memory checkAddresses
    )
        internal
    {
        _initController(controllerInst, configAddresses, checkAddresses);

        IALMProxy   almProxy   = IALMProxy(controllerInst.almProxy);
        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        require(configAddresses.oldController != address(0), "ForeignControllerInit/old-controller-zero-address");

        require(almProxy.hasRole(almProxy.CONTROLLER(), configAddresses.oldController),     "ForeignControllerInit/old-controller-not-almProxy-controller");
        require(rateLimits.hasRole(rateLimits.CONTROLLER(), configAddresses.oldController), "ForeignControllerInit/old-controller-not-rateLimits-controller");

        almProxy.revokeRole(almProxy.CONTROLLER(), configAddresses.oldController);
        rateLimits.revokeRole(rateLimits.CONTROLLER(), configAddresses.oldController);
    }

    /**********************************************************************************************/
    /*** Private helper functions                                                               ***/
    /**********************************************************************************************/

    function _initController(
        ControllerInstance  memory controllerInst,
        ConfigAddressParams memory configAddresses,
        CheckAddressParams  memory checkAddresses
    )
        private
    {
        // Step 1: Perform controller sanity checks

        ForeignController controller = ForeignController(controllerInst.controller);

        require(controller.hasRole(DEFAULT_ADMIN_ROLE, checkAddresses.admin), "ForeignControllerInit/incorrect-admin-controller");

        require(controller.proxy()      == controllerInst.almProxy,   "ForeignControllerInit/incorrect-almProxy");
        require(controller.rateLimits() == controllerInst.rateLimits, "ForeignControllerInit/incorrect-rateLimits");

        require(configAddresses.oldController != address(controller), "ForeignControllerInit/old-controller-is-new-controller");

        // Step 2: Configure ACL permissions controller, almProxy, and rateLimits

        IALMProxy   almProxy   = IALMProxy(controllerInst.almProxy);
        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        almProxy.grantRole(almProxy.CONTROLLER(),     address(controller));
        controller.grantRole(controller.FREEZER(),    configAddresses.freezer);
        rateLimits.grantRole(rateLimits.CONTROLLER(), address(controller));

        for (uint256 i; i < configAddresses.relayers.length; ++i) {
            controller.grantRole(controller.RELAYER(), configAddresses.relayers[i]);
        }
    }

}
