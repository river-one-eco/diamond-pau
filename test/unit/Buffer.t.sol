// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Address } from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import { IBuffer } from "../../src/facets/IBuffer.sol";

import { Buffer } from "../../src/facets/Buffer.sol";

contract Buffer_Tests is Test {

    address internal deployer     = makeAddr("deployer");
    address internal target       = makeAddr("target");
    address internal unauthorized = makeAddr("unauthorized");

    Buffer internal buffer;

    function setUp() external {
        vm.prank(deployer);
        buffer = new Buffer();
    }

    /**********************************************************************************************/
    /*** Initial State Tests                                                                    ***/
    /**********************************************************************************************/

    function test_constructor() external view {
        assertEq(buffer.admin(), deployer);
    }

    /**********************************************************************************************/
    /*** doCall Tests                                                                           ***/
    /**********************************************************************************************/

    function test_doCall_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IBuffer.NotAdmin.selector, unauthorized, deployer));
        vm.prank(unauthorized);
        buffer.doCall(target, "");
    }

    function test_doCall_targetReverts() external {
        bytes memory callData   = abi.encodeWithSignature("foo(uint256)", 42);
        bytes memory revertData = bytes("Some Revert");

        vm.mockCallRevert(target, callData, revertData);

        vm.expectRevert(revertData);
        vm.prank(deployer);
        buffer.doCall(target, callData);
    }

    function test_doCall() external {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", 42);

        uint256 expectedReturn = 84;

        _expectAndMockCall(target, callData, abi.encode(expectedReturn));

        vm.prank(deployer);
        bytes memory returnData = buffer.doCall(target, callData);

        assertEq(abi.decode(returnData, (uint256)), expectedReturn);
    }

    /**********************************************************************************************/
    /*** doCallWithValue Tests                                                                  ***/
    /**********************************************************************************************/

    function test_doCallWithValue_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IBuffer.NotAdmin.selector, unauthorized, deployer));
        vm.prank(unauthorized);
        buffer.doCallWithValue(target, "", 0);
    }

    function test_doCallWithValue_targetReverts() external {
        uint256 value = 1 ether;

        bytes memory callData   = abi.encodeWithSignature("foo(uint256)", 42);
        bytes memory revertData = bytes("Some Revert");

        deal(address(buffer), value);

        vm.mockCallRevert(target, value, callData, revertData);

        vm.expectRevert(revertData);
        vm.prank(deployer);
        buffer.doCallWithValue(target, callData, value);
    }

    function test_doCallWithValue() external {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", 42);

        uint256 expectedReturn = 84;
        uint256 value = 1 ether;

        deal(address(buffer), value);

        _expectAndMockCall(target, value, callData, abi.encode(expectedReturn));

        vm.prank(deployer);
        bytes memory returnData = buffer.doCallWithValue(target, callData, value);

        assertEq(abi.decode(returnData, (uint256)), expectedReturn);
    }

    function test_doCallWithValue_msgValue() external {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", 42);

        uint256 expectedReturn = 84;
        uint256 value = 1 ether;

        deal(deployer, value);

        _expectAndMockCall(target, value, callData, abi.encode(expectedReturn));

        vm.prank(deployer);
        bytes memory returnData = buffer.doCallWithValue{value: value}(target, callData, value);

        assertEq(abi.decode(returnData, (uint256)), expectedReturn);
    }

    /**********************************************************************************************/
    /*** doDelegateCall Tests                                                                   ***/
    /**********************************************************************************************/

    function test_doDelegateCall_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IBuffer.NotAdmin.selector, unauthorized, deployer));
        vm.prank(unauthorized);
        buffer.doDelegateCall(target, "");
    }

    function test_doDelegateCall_targetReverts() external {
        bytes memory callData   = abi.encodeWithSignature("foo(uint256)", 42);
        bytes memory revertData = bytes("Some Revert");

        vm.mockCallRevert(target, callData, revertData);

        vm.expectRevert(revertData);
        vm.prank(deployer);
        buffer.doDelegateCall(target, callData);
    }

    function test_doDelegateCall() external {
        bytes memory callData = abi.encodeWithSignature("foo(uint256)", 42);

        uint256 expectedReturn = 84;

        vm.mockCall(target, callData, abi.encode(expectedReturn));

        vm.prank(deployer);
        bytes memory returnData = buffer.doDelegateCall(target, callData);

        assertEq(abi.decode(returnData, (uint256)), expectedReturn);
    }

    /**********************************************************************************************/
    /*** Receive function Tests                                                                 ***/
    /**********************************************************************************************/

    function test_receive() external {
        deal(deployer, 1 ether);

        assertEq(deployer.balance,        1 ether);
        assertEq(address(buffer).balance, 0);

        vm.prank(deployer);
        payable(address(buffer)).transfer(1 ether);

        assertEq(deployer.balance,        0);
        assertEq(address(buffer).balance, 1 ether);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _expectAndMockCall(
        address        target,
        bytes   memory callData,
        bytes   memory returnData
    ) internal {
        vm.expectCall(target, callData);
        vm.mockCall(target, callData, returnData);
    }

    function _expectAndMockCall(
        address        target,
        uint256        value,
        bytes   memory callData,
        bytes   memory returnData
    ) internal {
        vm.expectCall(target, value, callData);
        vm.mockCall(target, value, callData, returnData);
    }

}
