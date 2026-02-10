// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

abstract contract DaiUsds_TestBase is ForkTestBase {

    IERC20Like internal constant DAI  = IERC20Like(Ethereum.DAI);
    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    uint256 internal daiSupply;
    uint256 internal usdsSupply;

    function setUp() public override {
        super.setUp();

        daiSupply  = DAI.totalSupply();
        usdsSupply = USDS.totalSupply();
    }

}

contract MainnetController_DAIUSDS_SwapUSDSToDAI_Tests is DaiUsds_TestBase {

    function test_swapUSDSToDAI_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI() external {
        deal(Ethereum.USDS, almProxy, 1_000_000e18);

        assertEq(USDS.balanceOf(almProxy), 1_000_000e18);
        assertEq(USDS.totalSupply(),       usdsSupply);  // Supply not updated on deal

        assertEq(DAI.balanceOf(almProxy), 0);
        assertEq(DAI.totalSupply(),       daiSupply);

        assertEq(USDS.allowance(almProxy, Ethereum.DAI_USDS), 0);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.swapUSDSToDAI(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(almProxy), 0);
        assertEq(USDS.totalSupply(),       usdsSupply - 1_000_000e18);

        assertEq(DAI.balanceOf(almProxy), 1_000_000e18);
        assertEq(DAI.totalSupply(),       daiSupply + 1_000_000e18);

        assertEq(USDS.allowance(almProxy, Ethereum.DAI_USDS), 0);
    }

}

contract MainnetController_DAIUSDS_SwapDAIToUSDS_Tests is DaiUsds_TestBase {

    function test_swapDAIToUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS() external {
        deal(Ethereum.DAI, almProxy, 1_000_000e18);

        assertEq(USDS.balanceOf(almProxy), 0);
        assertEq(USDS.totalSupply(),       usdsSupply);

        assertEq(DAI.balanceOf(almProxy), 1_000_000e18);
        assertEq(DAI.totalSupply(),       daiSupply);  // Supply not updated on deal

        assertEq(DAI.allowance(almProxy, Ethereum.DAI_USDS), 0);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.swapDAIToUSDS(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(almProxy), 1_000_000e18);
        assertEq(USDS.totalSupply(),       usdsSupply + 1_000_000e18);

        assertEq(DAI.balanceOf(almProxy), 0);
        assertEq(DAI.totalSupply(),       daiSupply - 1_000_000e18);

        assertEq(DAI.allowance(almProxy, Ethereum.DAI_USDS), 0);
    }

}
