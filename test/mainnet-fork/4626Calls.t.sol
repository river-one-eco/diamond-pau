// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

import { ForkTestBase }   from "./ForkTestBase.t.sol";
import { Vault_TestBase } from "./VaultCalls.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IERC4626Like is IERC20Like {

    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function previewRedeem(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 shares) external view returns (uint256);

    function totalAssets() external view returns (uint256);

}

abstract contract ERC4626_SUSDS_TestBase is Vault_TestBase {

    IERC4626Like internal constant SUSDS = IERC4626Like(Ethereum.SUSDS);

    uint256 internal susdsConvertedAssets;
    uint256 internal susdsConvertedShares;

    uint256 internal susdsTotalAssets;
    uint256 internal susdsTotalSupply;

    uint256 internal susdsDripAmount;

    bytes32 internal depositKey;
    bytes32 internal withdrawKey;

    uint256 internal usdsInSUSDS;

    function setUp() override public {
        super.setUp();

        usdsInSUSDS = USDS.balanceOf(Ethereum.SUSDS);

        depositKey  = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  Ethereum.SUSDS);
        withdrawKey = makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), Ethereum.SUSDS);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(), 10_000_000e18, uint256(10_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.setMaxExchangeRate(Ethereum.SUSDS, SUSDS.convertToShares(1e18), 1.2e18);
        vm.stopPrank();

        susdsConvertedAssets = SUSDS.convertToAssets(1e18);
        susdsConvertedShares = SUSDS.convertToShares(1e18);

        susdsTotalAssets = SUSDS.totalAssets();
        susdsTotalSupply = SUSDS.totalSupply();

        // Setting this value directly because SUSDS.drip() fails in setUp with
        // StateChangeDuringStaticCall and it is unclear why, something related to foundry.
        susdsDripAmount = 849.454677397481388011e18;

        assertEq(susdsConvertedAssets, 1.003430776383974596e18);
        assertEq(susdsConvertedShares, 0.996580953599671364e18);

        assertEq(susdsTotalAssets, 485_597_342.757158870618550128e18);
        assertEq(susdsTotalSupply, 483_937_062.910395855928183397e18);
    }

}

contract MainnetController_ERC4626_Deposit_Tests is ERC4626_SUSDS_TestBase {

    function test_depositERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositERC4626(Ethereum.SUSDS, 1e18, 0);
    }

    function test_depositERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.depositERC4626(Ethereum.SUSDS, 1e18, 0);
    }

    function test_depositERC4626_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.depositERC4626(makeAddr("fake-token"), 1e18, 0);
    }

    function test_depositERC4626_rateLimitBoundary() external {
        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18 + 1, 0);

        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, 0);

        vm.stopPrank();
    }

    function test_depositERC4626_exchangeRateBoundary() external {
        vm.prank(RELAYER);
        mainnetController.mintUSDS(5_000_000e18);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(
            Ethereum.SUSDS,
            SUSDS.convertToShares(5_000_000e18),
            5_000_000e18 - 1
        );
        vm.stopPrank();

        vm.expectRevert("ERC4626Lib/exchange-rate-too-high");
        vm.prank(RELAYER);
        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(
            Ethereum.SUSDS,
            SUSDS.convertToShares(5_000_000e18),
            5_000_000e18
        );
        vm.stopPrank();

        vm.prank(RELAYER);
        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, 0);
    }

    function test_depositERC4626_zeroExchangeRate() external {
        vm.prank(RELAYER);
        mainnetController.mintUSDS(5_000_000e18);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(Ethereum.SUSDS, 0, 0);

        vm.expectRevert("ERC4626Lib/exchange-rate-too-high");
        vm.prank(RELAYER);
        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, 0);
    }

    function test_depositERC4626_minSharesOutNotMetBoundary() external {
        uint256 overBoundaryShares = SUSDS.convertToShares(5_000_000e18) + 1;
        uint256 atBoundaryShares   = SUSDS.convertToShares(5_000_000e18);

        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(5_000_000e18);

        vm.expectRevert("ERC4626Lib/min-shares-out-not-met");
        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, overBoundaryShares);

        mainnetController.depositERC4626(Ethereum.SUSDS, 5_000_000e18, atBoundaryShares);

        vm.stopPrank();
    }

    function test_depositERC4626() external {
        vm.prank(RELAYER);
        mainnetController.mintUSDS(1e18);

        assertEq(USDS.balanceOf(almProxy),                   1e18);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS);

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets);
        assertEq(SUSDS.balanceOf(almProxy), 0);

        vm.record();

        vm.prank(RELAYER);
        uint256 shares = mainnetController.depositERC4626(
            Ethereum.SUSDS,
            1e18,
            susdsConvertedShares
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, susdsConvertedShares);

        assertEq(USDS.balanceOf(almProxy),                   0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS + susdsDripAmount + 1e18);

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply + shares);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets + 1e18);
        assertEq(SUSDS.balanceOf(almProxy), susdsConvertedShares);
    }

}

contract MainnetController_ERC4626_Withdraw_Tests is ERC4626_SUSDS_TestBase {

    function test_withdrawERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 1e18, 1e18);
    }

    function test_withdrawERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 1e18, 1e18);
    }

    function test_withdrawERC4626_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.withdrawERC4626(makeAddr("fake-token"), 1e18, 1e18);
    }

    function test_withdrawERC4626_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);

        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(10_000_000e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10_000_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 5_000_000e18 + 1, 5_000_000e18 + 1);

        mainnetController.withdrawERC4626(Ethereum.SUSDS, 5_000_000e18, 5_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawERC4626_maxSharesInNotMetBoundary() external {
        uint256 underBoundaryShares = SUSDS.previewWithdraw(1_000_000e18) - 1;
        uint256 atBoundaryShares    = SUSDS.previewWithdraw(1_000_000e18);

        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(2_000_000e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 2_000_000e18, 0);

        vm.expectRevert("ERC4626Lib/shares-burned-too-high");
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 1_000_000e18, underBoundaryShares);

        mainnetController.withdrawERC4626(Ethereum.SUSDS, 1_000_000e18, atBoundaryShares);

        vm.stopPrank();
    }

    function test_withdrawERC4626() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  Ethereum.SUSDS);
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), Ethereum.SUSDS);

        vm.startPrank(RELAYER);
        mainnetController.mintUSDS(1e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 1e18, susdsConvertedShares);
        vm.stopPrank();

        assertEq(USDS.balanceOf(almProxy),                   0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS + susdsDripAmount + 1e18);

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply + susdsConvertedShares);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets + 1e18);
        assertEq(SUSDS.balanceOf(almProxy), susdsConvertedShares);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        // Max available with rounding
        vm.prank(RELAYER);
        uint256 shares = mainnetController.withdrawERC4626(
            Ethereum.SUSDS,
            1e18 - 1,
            susdsConvertedShares
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(shares, susdsConvertedShares);

        assertEq(USDS.balanceOf(almProxy),                   1e18 - 1);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS + susdsDripAmount + 1);  // Rounding

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets);
        assertEq(SUSDS.balanceOf(almProxy), 0);
    }

}

contract MainnetController_ERC4626_Redeem_Tests is ERC4626_SUSDS_TestBase {

    function test_redeemERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.redeemERC4626(Ethereum.SUSDS, 1e18, 1e18);
    }

    function test_redeemERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.redeemERC4626(Ethereum.SUSDS, 1e18, 1e18);
    }

    function test_redeemERC4626_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            makeAddressKey(
                mainnetController.LIMIT_4626_WITHDRAW(),
                Ethereum.SUSDS
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.startPrank(RELAYER);
        mainnetController.mintUSDS(100e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 100e18, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.redeemERC4626(Ethereum.SUSDS, 1e18, 1e18);
    }

    function test_redeemERC4626_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);

        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(10_000_000e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10_000_000e18, 0);

        uint256 overBoundaryShares = SUSDS.convertToShares(5_000_000e18 + 2);
        uint256 atBoundaryShares   = SUSDS.convertToShares(5_000_000e18 + 1);  // Still rounds down

        assertEq(SUSDS.previewRedeem(overBoundaryShares), 5_000_000e18 + 1);
        assertEq(SUSDS.previewRedeem(atBoundaryShares),   5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.redeemERC4626(Ethereum.SUSDS, overBoundaryShares, 1e18);

        mainnetController.redeemERC4626(Ethereum.SUSDS, atBoundaryShares, 1e18);

        vm.stopPrank();
    }

    function test_redeemERC4626_minAssetsOutNotMetBoundary() external {
        vm.startPrank(RELAYER);

        mainnetController.mintUSDS(2_000_000e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 2_000_000e18, 0);

        uint256 shares = SUSDS.convertToShares(2_000_000e18);

        uint256 overBoundaryAssets = SUSDS.convertToAssets(shares) + 1;
        uint256 atBoundaryAssets   = SUSDS.convertToAssets(shares);

        vm.expectRevert("ERC4626Lib/min-assets-out-not-met");
        mainnetController.redeemERC4626(Ethereum.SUSDS, shares, overBoundaryAssets);

        mainnetController.redeemERC4626(Ethereum.SUSDS, shares, atBoundaryAssets);

        vm.stopPrank();
    }

    function test_redeemERC4626() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  Ethereum.SUSDS);
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), Ethereum.SUSDS);

        vm.startPrank(RELAYER);
        mainnetController.mintUSDS(1e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 1e18, susdsConvertedShares);
        vm.stopPrank();

        assertEq(USDS.balanceOf(almProxy),                   0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS + susdsDripAmount + 1e18);

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply + susdsConvertedShares);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets + 1e18);
        assertEq(SUSDS.balanceOf(almProxy), susdsConvertedShares);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        vm.prank(RELAYER);
        uint256 assets = mainnetController.redeemERC4626(
            Ethereum.SUSDS,
            susdsConvertedShares,
            1e18 - 1 // Rounding
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(assets, 1e18 - 1);  // Rounding

        assertEq(USDS.balanceOf(almProxy),                   1e18 - 1);  // Rounding
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.balanceOf(Ethereum.SUSDS),             usdsInSUSDS + susdsDripAmount + 1);  // Rounding

        assertEq(USDS.allowance(buffer,   vault),          type(uint256).max);
        assertEq(USDS.allowance(almProxy, Ethereum.SUSDS), 0);

        assertEq(SUSDS.totalSupply(),       susdsTotalSupply);
        assertEq(SUSDS.totalAssets(),       susdsTotalAssets);
        assertEq(SUSDS.balanceOf(almProxy), 0);
    }

}
