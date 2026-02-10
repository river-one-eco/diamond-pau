// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

// TODO: Delete this file

import { ALMProxy }          from "../src/ALMProxy.sol";
import { ForeignController } from "../src/ForeignController.sol";
import { MainnetController } from "../src/MainnetController.sol";
import { RateLimits }        from "../src/RateLimits.sol";

import { ControllerInstance } from "./ControllerInstance.sol";

library ForeignControllerDeploy {

    function deployController(address admin, address almProxy, address rateLimits)
        internal
        returns (address controller)
    {
        controller = address(new ForeignController(admin, almProxy, rateLimits));
    }

    function deployFull(address admin) internal returns (ControllerInstance memory instance) {
        instance.almProxy   = address(new ALMProxy(admin));
        instance.rateLimits = address(new RateLimits(admin));
        instance.controller = address(new ForeignController(admin, instance.almProxy, instance.rateLimits));
    }

}

library MainnetControllerDeploy {

    function deployController(address admin, address almProxy, address rateLimits)
        internal
        returns (address controller)
    {
        return address(new MainnetController(admin, almProxy, rateLimits));
    }

    function deployFull(address admin) internal returns (ControllerInstance memory instance) {
        instance.almProxy   = address(new ALMProxy(admin));
        instance.rateLimits = address(new RateLimits(admin));
        instance.controller = address(new MainnetController(admin, instance.almProxy, instance.rateLimits));
    }

}
