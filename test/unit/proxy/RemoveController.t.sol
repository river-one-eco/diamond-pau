// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract Freezable_RemoveController_TestBase is UnitTestBase {

    ALMProxyFreezable internal almProxyFreezable;

    address internal target;

    address internal controller     = makeAddr("controller");
    address internal exampleAddress = makeAddr("exampleAddress");

    bytes internal data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxyFreezable = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxyFreezable.grantRole(FREEZER,    freezer);
        almProxyFreezable.grantRole(CONTROLLER, controller);
        vm.stopPrank();

        target = address(new MockTarget());
    }

}

contract ALMProxy_Freezable_RemoveController_Tests is Freezable_RemoveController_TestBase {

    function test_removeController_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        almProxyFreezable.removeController(controller);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        vm.prank(admin);
        almProxyFreezable.removeController(controller);
    }

    function test_removeController() external {
        // ALM Proxy Freezable is msg.sender, target emits the event
        vm.expectEmit(target);
        emit MockTarget.ExampleEvent(exampleAddress, 42, 84, address(almProxyFreezable), 0);

        vm.prank(controller);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);

        // Before has controller role
        assertTrue(almProxyFreezable.hasRole(CONTROLLER, controller));

        // Freezer comes in and removes controller.
        vm.expectEmit(address(almProxyFreezable));
        emit ALMProxyFreezable.ControllerRemoved(controller);

        vm.prank(freezer);
        almProxyFreezable.removeController(controller);

        // After no longer has controller role
        assertFalse(almProxyFreezable.hasRole(CONTROLLER, controller));

        // After can no longer call as controller
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            controller,
            CONTROLLER
        ));
        vm.prank(controller);
        almProxyFreezable.doCall(target, data);
    }

}
