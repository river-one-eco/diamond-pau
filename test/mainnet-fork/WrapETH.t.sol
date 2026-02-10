// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

contract MainnetController_WrapAllProxyETH_Tests is ForkTestBase {

    IERC20Like internal constant WETH = IERC20Like(Ethereum.WETH);

    function test_wrapAllProxyETH_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wrapAllProxyETH();
    }

    function test_wrapAllProxyETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.wrapAllProxyETH();
    }

    function test_wrapAllProxyETH_zeroBalance() external {
        vm.skip(true); // TODO: Undo

        assertEq(almProxy.balance,         0);
        assertEq(WETH.balanceOf(almProxy), 0);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(almProxy.balance,         0);
        assertEq(WETH.balanceOf(almProxy), 0);
    }

    function test_wrapAllProxyETH() external {
        vm.deal(almProxy, 1 ether);

        assertEq(almProxy.balance,         1 ether);
        assertEq(WETH.balanceOf(almProxy), 0);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(almProxy.balance,         0);
        assertEq(WETH.balanceOf(almProxy), 1 ether);
    }

}
