// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { MainnetController } from "../../../src/MainnetController.sol";
import { ForeignController } from "../../../src/ForeignController.sol";

import { MockPSM3 } from "../mocks/MockPSM3.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract MainnetController_RemoveRelayer_Tests is UnitTestBase {

    MainnetController internal controller;

    address internal relayer1 = makeAddr("relayer1");
    address internal relayer2 = makeAddr("relayer2");

    function setUp() public virtual {
        controller = new MainnetController(admin, makeAddr("almProxy"), makeAddr("rateLimits"));

        vm.startPrank(admin);

        controller.grantRole(FREEZER, freezer);
        controller.grantRole(RELAYER, relayer1);
        controller.grantRole(RELAYER, relayer2);

        vm.stopPrank();
    }

    function test_removeRelayer_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        controller.removeRelayer(relayer);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        vm.prank(admin);
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer() external {
        assertEq(controller.hasRole(RELAYER, relayer1), true);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.expectEmit(address(controller));
        emit MainnetController.RelayerRemoved(relayer1);

        vm.prank(freezer);
        controller.removeRelayer(relayer1);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.record();

        vm.expectEmit(address(controller));
        emit MainnetController.RelayerRemoved(relayer2);

        vm.prank(freezer);
        controller.removeRelayer(relayer2);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), false);
    }

}

contract ForeignController_RemoveRelayer_Tests is UnitTestBase {

    ForeignController internal controller;

    address internal relayer1 = makeAddr("relayer1");
    address internal relayer2 = makeAddr("relayer2");

    function setUp() public {
        controller = new ForeignController(admin, makeAddr("almProxy"), makeAddr("rateLimits"));

        vm.startPrank(admin);

        controller.grantRole(FREEZER, freezer);
        controller.grantRole(RELAYER, relayer1);
        controller.grantRole(RELAYER, relayer2);

        vm.stopPrank();
    }

    function test_removeRelayer_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        controller.removeRelayer(relayer);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        vm.prank(admin);
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer() external {
        assertEq(controller.hasRole(RELAYER, relayer1), true);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.expectEmit(address(controller));
        emit ForeignController.RelayerRemoved(relayer1);

        vm.prank(freezer);
        controller.removeRelayer(relayer1);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.record();

        vm.expectEmit(address(controller));
        emit ForeignController.RelayerRemoved(relayer2);

        vm.prank(freezer);
        controller.removeRelayer(relayer2);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), false);
    }

}
