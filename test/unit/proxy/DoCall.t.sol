// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract ALMProxy_Call_TestBase is UnitTestBase {

    ALMProxy internal almProxy;

    address internal target;

    address internal controller     = makeAddr("controller");
    address internal exampleAddress = makeAddr("exampleAddress");

    bytes internal data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxy = new ALMProxy(admin);

        vm.prank(admin);
        almProxy.grantRole(CONTROLLER_ROLE, controller);

        target = address(new MockTarget());
    }

}

contract ALMProxy_DoCall_Tests is ALMProxy_Call_TestBase {

    function test_doCall_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doCall(target, data);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        vm.prank(admin);
        almProxy.doCall(target, data);
    }

    function test_doCall() external {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit MockTarget.ExampleEvent(exampleAddress, 42, 84, address(almProxy), 0);

        vm.prank(controller);
        bytes memory returnData = almProxy.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_DoCallWithValue_Tests is ALMProxy_Call_TestBase {

    function test_doCallWithValue_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        vm.prank(admin);
        almProxy.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_notEnoughBalanceBoundary() external {
        vm.deal(address(almProxy), 1e18 - 1);

        vm.expectRevert(abi.encodeWithSignature(
            "AddressInsufficientBalance(address)",
            address(almProxy)
        ));
        vm.prank(controller);
        almProxy.doCallWithValue(target, data, 1e18);

        vm.deal(address(almProxy), 1e18);

        vm.prank(controller);
        almProxy.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue() external {
        vm.deal(address(almProxy), 1e18);

        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit MockTarget.ExampleEvent(exampleAddress, 42, 84, address(almProxy), 1e18);

        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() external {
        vm.deal(controller, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit MockTarget.ExampleEvent(exampleAddress, 42, 84, address(almProxy), 1e18);

        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue{value: 1e18}(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_DoDelegateCall_Tests is ALMProxy_Call_TestBase {

    function test_doDelegateCall_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doDelegateCall(target, data);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        vm.prank(admin);
        almProxy.doDelegateCall(target, data);
    }

    function test_doDelegateCall() external {
        // L1 Controller is msg.sender, almProxy emits the event
        vm.expectEmit(address(almProxy));
        emit MockTarget.ExampleEvent(exampleAddress, 42, 84, controller, 0);

        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_Freezable_Tests is
    ALMProxy_DoCall_Tests,
    ALMProxy_DoCallWithValue_Tests,
    ALMProxy_DoDelegateCall_Tests
{

    function setUp() public override {
        super.setUp();

        // Overwrite almProxy with ALMProxyFreezable to demonstrate equivalent functionality
        almProxy = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxy.grantRole(FREEZER_ROLE,    freezer);
        almProxy.grantRole(CONTROLLER_ROLE, controller);
        vm.stopPrank();
    }

}
