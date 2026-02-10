// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { MainnetController_Ethena_E2ETests } from "./Ethena.t.sol";
import { Maple_TestBase }                    from "./Maple.t.sol";

interface ISUSDELike {

    function silo() external view returns(address);

}


contract MainnetController_Ethena_Attack_Tests is MainnetController_Ethena_E2ETests {

    function test_attack_compromisedRelayer_lockingFundsInEthenaSilo() external {
        deal(Ethereum.SUSDE, almProxy, 1_000_000e18);

        address silo = ISUSDELike(Ethereum.SUSDE).silo();

        uint256 startingSiloBalance = USDE.balanceOf(silo);

        vm.prank(RELAYER);
        mainnetController.cooldownAssetsSUSDE(1_000_000e18);

        skip(7 days);

        // Relayer is now compromised and wants to lock funds in the silo
        vm.prank(RELAYER);
        mainnetController.cooldownAssetsSUSDE(1);

        // Real relayer cannot withdraw when they want to
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        vm.prank(RELAYER);
        mainnetController.unstakeSUSDE();

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(FREEZER);
        mainnetController.removeRelayer(RELAYER);

        skip(7 days);

        // Compromised relayer cannot perform attack anymore
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            RELAYER,
            RELAYER_ROLE
        ));
        vm.prank(RELAYER);
        mainnetController.cooldownAssetsSUSDE(1);

        // Funds have been locked in the silo this whole time
        assertEq(USDE.balanceOf(almProxy), 0);
        assertEq(USDE.balanceOf(silo),              startingSiloBalance + 1_000_000e18 + 1);  // 1 wei deposit as well

        // Backstop relayer can unstake the funds
        vm.prank(backstopRelayer);
        mainnetController.unstakeSUSDE();

        assertEq(USDE.balanceOf(almProxy), 1_000_000e18 + 1);
        assertEq(USDE.balanceOf(silo),              startingSiloBalance);
    }

}

contract MainnetController_Maple_Attack_Tests is Maple_TestBase {

    function test_attack_compromisedRelayer_delayRequestMapleRedemption() external {
        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        vm.prank(RELAYER);
        mainnetController.depositERC4626(Ethereum.SYRUP_USDC, 1_000_000e6, 0);

        // Malicious relayer delays the request for redemption for 1m
        // because new requests can't be fulfilled until the previous is fulfilled or cancelled
        vm.prank(RELAYER);
        mainnetController.requestMapleRedemption(Ethereum.SYRUP_USDC, 1);

        // Cannot process request
        vm.expectRevert("WM:AS:IN_QUEUE");
        vm.prank(RELAYER);
        mainnetController.requestMapleRedemption(Ethereum.SYRUP_USDC, 500_000e6);

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(FREEZER);
        mainnetController.removeRelayer(RELAYER);

        // Compromised relayer cannot perform attack anymore
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            RELAYER,
            RELAYER_ROLE
        ));
        vm.prank(RELAYER);
        mainnetController.requestMapleRedemption(Ethereum.SYRUP_USDC, 1);

        // Governance relayer can cancel and submit the real request
        vm.startPrank(backstopRelayer);
        mainnetController.cancelMapleRedemption(Ethereum.SYRUP_USDC, 1);
        mainnetController.requestMapleRedemption(Ethereum.SYRUP_USDC, 500_000e6);
        vm.stopPrank();
    }

}
