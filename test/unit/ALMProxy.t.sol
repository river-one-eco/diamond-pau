// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../src/interfaces/IALMProxy.sol";

import { ALMProxy } from "../../src/ALMProxy.sol";

import { UnitTests } from "./UnitTests.t.sol";

import { MockTarget, MockRevertingTarget, MockStorageWriter } from "../mocks/MockTarget.sol";

contract ALMProxy_Tests is UnitTests {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    ALMProxy almProxy;

    address target;

    address controller     = makeAddr("controller");
    address exampleAddress = makeAddr("exampleAddress");

    bytes data = abi.encodeWithSignature(
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

    /**********************************************************************************************/
    /*** constructor tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IALMProxy.ZeroAdmin.selector);
        new ALMProxy(address(0));
    }

    function test_constructor() external {
        ALMProxy newAlmProxy = new ALMProxy(admin);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** doCall tests                                                                           ***/
    /**********************************************************************************************/

    function test_doCall_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        almProxy.doCall(target, data);
    }

    function test_doCall_targetEmptyCode() external {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doCall(emptyTarget, "");
    }

    function test_doCall_revertsWithReason() external {
        address revertingTarget = address(new MockRevertingTarget());

        vm.expectRevert("MockRevertingTarget/reverted");
        vm.prank(controller);
        almProxy.doCall(revertingTarget, abi.encodeWithSignature("revertWithReason()"));
    }

    function test_doCall_revertsWithCustomError() external {
        address revertingTarget = address(new MockRevertingTarget());

        vm.expectRevert(MockRevertingTarget.MockError.selector);
        vm.prank(controller);
        almProxy.doCall(revertingTarget, abi.encodeWithSignature("revertWithCustomError()"));
    }

    function test_doCall() external {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 0
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    /**********************************************************************************************/
    /*** doCallWithValue tests                                                                  ***/
    /**********************************************************************************************/

    function test_doCallWithValue_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        almProxy.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_notEnoughBalanceBoundary() external {
        vm.deal(address(almProxy), 1e18 - 1);

        vm.startPrank(controller);

        vm.expectRevert(abi.encodeWithSignature(
            "AddressInsufficientBalance(address)",
            address(almProxy)
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.deal(address(almProxy), 1e18);

        almProxy.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_targetEmptyCode() external {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doCallWithValue(emptyTarget, "", 0);
    }

    function test_doCallWithValue() external {
        vm.deal(address(almProxy), 1e18);

        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 1e18
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() external {
        vm.deal(controller, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 1e18
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue{value: 1e18}(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    /**********************************************************************************************/
    /*** doDelegateCall tests                                                                   ***/
    /**********************************************************************************************/

    function test_doDelegateCall_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doDelegateCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        almProxy.doDelegateCall(target, data);
    }

    function test_doDelegateCall_targetEmptyCode() external {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doDelegateCall(emptyTarget, "");
    }

    function test_doDelegateCall() external {
        // L1 Controller is msg.sender, almProxy emits the event
        vm.expectEmit(address(almProxy));
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : controller,
            value          : 0
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doDelegateCall_writesToProxyStorage() external {
        address writer = address(new MockStorageWriter());

        uint256 slot  = 1000;
        uint256 value = 42;

        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(writer, abi.encodeWithSignature("write(uint256,uint256)", slot, value));

        address context = abi.decode(returnData, (address));

        // delegatecall executes in the proxy's storage context: the slot is written in the proxy,
        // and the target contract's own storage is untouched.
        assertEq(uint256(vm.load(address(almProxy), bytes32(slot))), value);
        assertEq(uint256(vm.load(writer,            bytes32(slot))), 0);
        assertEq(context,                           address(almProxy));
    }

    /**********************************************************************************************/
    /*** receiveETH tests                                                                       ***/
    /**********************************************************************************************/

    function test_receiveETH() external {
        ALMProxy almProxy = new ALMProxy(admin);

        deal(address(this), 10 ether);

        assertEq(address(this).balance,     10 ether);
        assertEq(address(almProxy).balance, 0);

        payable(address(almProxy)).transfer(10 ether);

        assertEq(address(this).balance,     0);
        assertEq(address(almProxy).balance, 10 ether);
    }

}
