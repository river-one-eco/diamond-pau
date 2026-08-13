// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxyFreezable } from "../../src/interfaces/IALMProxyFreezable.sol";

import { ALMProxyFreezable } from "../../src/ALMProxyFreezable.sol";

import { UnitTests } from "./UnitTests.t.sol";

import { MockTarget, MockRevertingTarget, MockStorageWriter } from "../mocks/MockTarget.sol";

contract ALMProxyFreezable_Tests is UnitTests {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    event AllocatorRemoved(address indexed allocator);

    ALMProxyFreezable almProxyFreezable;

    address target;

    address exampleAddress = makeAddr("exampleAddress");

    bytes data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxyFreezable = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxyFreezable.grantRole(FREEZER_ROLE,   freezer);
        almProxyFreezable.grantRole(ALLOCATOR_ROLE, allocator);
        vm.stopPrank();

        target = address(new MockTarget());
    }

    /**********************************************************************************************/
    /*** constructor tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IALMProxyFreezable.ZeroAdmin.selector);
        new ALMProxyFreezable(address(0));
    }

    function test_constructor() external {
        ALMProxyFreezable newAlmProxyFreezable = new ALMProxyFreezable(admin);

        assertEq(newAlmProxyFreezable.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** doCall tests                                                                           ***/
    /**********************************************************************************************/

    function test_doCall_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);
    }

    function test_doCall_revertsWithReason() external {
        address revertingTarget = address(new MockRevertingTarget());

        vm.prank(allocator);
        vm.expectRevert("MockRevertingTarget/reverted");
        almProxyFreezable.doCall(revertingTarget, abi.encodeWithSignature("revertWithReason()"));
    }

    function test_doCall() external {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 0
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    /**********************************************************************************************/
    /*** doCallWithValue tests                                                                  ***/
    /**********************************************************************************************/

    function test_doCallWithValue_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_notEnoughBalanceBoundary() external {
        vm.deal(address(almProxyFreezable), 1e18 - 1);

        vm.startPrank(allocator);

        vm.expectRevert(abi.encodeWithSignature(
            "AddressInsufficientBalance(address)",
            address(almProxyFreezable)
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);

        vm.deal(address(almProxyFreezable), 1e18);

        almProxyFreezable.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_revertsWithReason() external {
        address revertingTarget = address(new MockRevertingTarget());

        vm.deal(address(almProxyFreezable), 1e18);

        vm.prank(allocator);
        vm.expectRevert("MockRevertingTarget/reverted");
        almProxyFreezable.doCallWithValue(revertingTarget, abi.encodeWithSignature("revertWithReason()"), 1e18);
    }

    function test_doCallWithValue() external {
        vm.deal(address(almProxyFreezable), 1e18);

        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 1e18
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() external {
        vm.deal(allocator, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 1e18
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCallWithValue{value: 1e18}(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    /**********************************************************************************************/
    /*** removeAllocator tests                                                                  ***/
    /**********************************************************************************************/

    function test_removeAllocator_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER_ROLE
        ));
        almProxyFreezable.removeAllocator(allocator);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER_ROLE
        ));
        almProxyFreezable.removeAllocator(allocator);
    }

    function test_removeAllocator_notLiveAllocator() external {
        vm.prank(freezer);
        vm.expectRevert("ALMProxyFreezable/not-live-allocator");
        almProxyFreezable.removeAllocator(exampleAddress);
    }

    function test_removeAllocator() external {
        // ALM Proxy Freezable is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 0
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);

        // Before has allocator role
        assertTrue(almProxyFreezable.hasRole(ALLOCATOR_ROLE, allocator));

        // Freezer comes in and removes allocator.
        vm.prank(freezer);
        vm.expectEmit(address(almProxyFreezable));
        emit AllocatorRemoved(allocator);
        almProxyFreezable.removeAllocator(allocator);

        // After no longer has allocator role
        assertFalse(almProxyFreezable.hasRole(ALLOCATOR_ROLE, allocator));

        // After can no longer call as allocator
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            allocator,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);
    }

}
