// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IAaveV4Facet }     from "../../src/facets/aave-v4/IAaveV4Facet.sol";
import { IAaveV4SpokeLike } from "../../src/facets/aave-v4/AaveV4Facet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IAaveV4Hub {
    function getAssetLiquidity(uint256 assetId)  external view returns (uint256);
    function getAddedAssets(uint256 assetId)     external view returns (uint256);
    function getAddedShares(uint256 assetId)     external view returns (uint256);
    function getAssetDeficitRay(uint256 assetId) external view returns (uint256);
}

abstract contract AaveV4_TestBase is ForkTestBase {

    // USDC is suppliable on both the Main and Forex spokes via the same Core Hub asset (assetId 5),
    // which lets the tests exercise per-(spoke, reserveId) rate limits across two spokes for one asset.
    address internal constant MAIN_SPOKE  = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;
    address internal constant FOREX_SPOKE = 0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1;
    address internal constant CORE_HUB    = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

    uint256 internal constant MAIN_USDC_RESERVE_ID  = 7;  // USDC (6 decimals),  Core Hub assetId 5
    uint256 internal constant MAIN_WETH_RESERVE_ID  = 0;  // WETH (18 decimals), Core Hub assetId 0
    uint256 internal constant FOREX_USDC_RESERVE_ID = 1;  // USDC (6 decimals),  Core Hub assetId 5

    uint256 internal constant USDC_ASSET_ID = 5;
    uint256 internal constant WETH_ASSET_ID = 0;

    // Controller-side deposit limits sit above Aave's on-chain supply caps, so they only bind in the
    // dedicated rate-limit boundary tests.
    uint256 internal constant USDC_DEPOSIT_LIMIT = 25_000_000e6;
    uint256 internal constant WETH_DEPOSIT_LIMIT = 20_000e18;

    uint256 internal constant USDC_DEPOSIT_AMOUNT = 1_000_000e6;
    uint256 internal constant WETH_DEPOSIT_AMOUNT = 100e18;

    IERC20 internal weth = IERC20(Ethereum.WETH);

    bytes32 internal mainUsdcDepositKey;
    bytes32 internal mainUsdcWithdrawKey;
    bytes32 internal mainWethDepositKey;
    bytes32 internal mainWethWithdrawKey;
    bytes32 internal forexUsdcDepositKey;
    bytes32 internal forexUsdcWithdrawKey;

    uint256 internal startingHubBalanceUsdc;
    uint256 internal startingHubBalanceWeth;

    function setUp() public virtual override {
        super.setUp();

        mainUsdcDepositKey   = mainnetController.aaveV4_getDepositRateLimitKey(MAIN_SPOKE,   MAIN_USDC_RESERVE_ID, address(usdc));
        mainUsdcWithdrawKey  = mainnetController.aaveV4_getWithdrawRateLimitKey(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID);
        mainWethDepositKey   = mainnetController.aaveV4_getDepositRateLimitKey(MAIN_SPOKE,   MAIN_WETH_RESERVE_ID, address(weth));
        mainWethWithdrawKey  = mainnetController.aaveV4_getWithdrawRateLimitKey(MAIN_SPOKE,  MAIN_WETH_RESERVE_ID);
        forexUsdcDepositKey  = mainnetController.aaveV4_getDepositRateLimitKey(FOREX_SPOKE,  FOREX_USDC_RESERVE_ID, address(usdc));
        forexUsdcWithdrawKey = mainnetController.aaveV4_getWithdrawRateLimitKey(FOREX_SPOKE, FOREX_USDC_RESERVE_ID);

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(mainUsdcDepositKey,  USDC_DEPOSIT_LIMIT, USDC_DEPOSIT_LIMIT / 1 days);
        rateLimits.setRateLimitData(mainWethDepositKey,  WETH_DEPOSIT_LIMIT, WETH_DEPOSIT_LIMIT / 1 days);
        rateLimits.setRateLimitData(forexUsdcDepositKey, USDC_DEPOSIT_LIMIT, USDC_DEPOSIT_LIMIT / 1 days);

        rateLimits.setUnlimitedRateLimitData(mainUsdcWithdrawKey);
        rateLimits.setUnlimitedRateLimitData(mainWethWithdrawKey);
        rateLimits.setUnlimitedRateLimitData(forexUsdcWithdrawKey);

        // Per-(spoke, reserveId) slippage: each market gets its own rounding tolerance.
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID,  1e18 - 1e4);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE,  MAIN_WETH_RESERVE_ID,  1e18 - 1e4);
        mainnetController.aaveV4_setMaxSlippage(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 1e18 - 1e4);

        vm.stopPrank();

        startingHubBalanceUsdc = usdc.balanceOf(CORE_HUB);
        startingHubBalanceWeth = weth.balanceOf(CORE_HUB);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 25574000;  // July 2026 (Aave v4 live on mainnet since March 2026)
    }

    function _suppliedAssets(address spoke, uint256 reserveId) internal view returns (uint256) {
        return IAaveV4SpokeLike(spoke).getUserSuppliedAssets(reserveId, address(almProxy));
    }

}

// NOTE: Only testing USDC on the Main Spoke for non-rate-limit failures as the revert path is asset-
//       and spoke-agnostic.

contract MainnetController_AaveV4_Deposit_Tests is AaveV4_TestBase {

    function test_depositAaveV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);
    }

    function test_depositAaveV4_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);
    }

    function test_depositAaveV4_zeroMaxSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 0);

        deal(Ethereum.USDC, address(almProxy), 1_000e6);

        vm.expectRevert("AaveV4Facet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);
    }

    function test_depositAaveV4_slippageTooHigh() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        // Force the measured supplied delta to zero so the post-supply guard trips under a valid
        // (< 1e18) tolerance, exercising the slippage check independent of real market rounding.
        vm.mockCall(
            MAIN_SPOKE,
            abi.encodeWithSelector(
                IAaveV4SpokeLike.getUserSuppliedAssets.selector,
                MAIN_USDC_RESERVE_ID,
                address(almProxy)
            ),
            abi.encode(uint256(0))
        );

        vm.expectRevert("AaveV4Facet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    // Pins the rationale for bounding setMaxSlippage strictly below 1e18: once a reserve accrues
    // interest its share price rises above 1:1, so a 1e18 (exact 1:1) tolerance would revert every
    // deposit. The setter forbids 1e18 outright, and the max valid tolerance still admits deposits.
    function test_depositAaveV4_usdcSlippageOneToOneAfterAccrual() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        skip(365 days);

        // Interest accrued: the supplied position now exceeds the original deposit (share price > 1:1).
        assertGt(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT);

        // An exact 1:1 requirement is unrepresentable (the setter rejects 1e18, covered in the
        // integration suite), so accrual can never wedge deposits: a tolerance just below 1e18
        // still clears an honest deposit.
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 0.99e18);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
    }

    function test_depositAaveV4_assetDeficit() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        // Simulate an outstanding Hub deficit for USDC (assetId 5): any deficit blocks the deposit.
        vm.mockCall(
            CORE_HUB,
            abi.encodeWithSelector(IAaveV4Hub.getAssetDeficitRay.selector, USDC_ASSET_ID),
            abi.encode(uint256(1))
        );

        vm.expectRevert("AaveV4Facet/asset-deficit");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        // The guard is hardcoded to zero with no admin override, so the deposit only clears once the
        // deficit itself is gone.
        vm.clearMockedCalls();

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT, 2);
    }

    function test_depositAaveV4_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_LIMIT + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_LIMIT + 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_wethRateLimitedBoundary() external {
        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_LIMIT + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_LIMIT + 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey), WETH_DEPOSIT_LIMIT - WETH_DEPOSIT_AMOUNT);
    }

    // Guards the IAaveV4SpokeLike.Reserve layout assumed by the partial interface, across both spokes.
    function test_aaveV4_reserveLayout() external view {
        IAaveV4SpokeLike.Reserve memory mainUsdc = IAaveV4SpokeLike(MAIN_SPOKE).getReserve(MAIN_USDC_RESERVE_ID);
        assertEq(mainUsdc.underlying, address(usdc));
        assertEq(mainUsdc.hub,        CORE_HUB);
        assertEq(mainUsdc.assetId,    USDC_ASSET_ID);
        assertEq(mainUsdc.decimals,   6);

        IAaveV4SpokeLike.Reserve memory mainWeth = IAaveV4SpokeLike(MAIN_SPOKE).getReserve(MAIN_WETH_RESERVE_ID);
        assertEq(mainWeth.underlying, address(weth));
        assertEq(mainWeth.hub,        CORE_HUB);
        assertEq(mainWeth.assetId,    WETH_ASSET_ID);
        assertEq(mainWeth.decimals,   18);

        // Same underlying and Hub as the Main Spoke USDC reserve, but on a different spoke.
        IAaveV4SpokeLike.Reserve memory forexUsdc = IAaveV4SpokeLike(FOREX_SPOKE).getReserve(FOREX_USDC_RESERVE_ID);
        assertEq(forexUsdc.underlying, address(usdc));
        assertEq(forexUsdc.hub,        CORE_HUB);
        assertEq(forexUsdc.assetId,    USDC_ASSET_ID);
        assertEq(forexUsdc.decimals,   6);
    }

    // Verifies the Hub.getAssetDeficitRay signature used by the deposit guard and confirms the tested
    // markets are deficit-free, so the hardcoded zero-deficit guard does not block honest deposits.
    function test_aaveV4_marketsHaveNoDeficit() external view {
        assertEq(IAaveV4Hub(CORE_HUB).getAssetDeficitRay(USDC_ASSET_ID), 0);
        assertEq(IAaveV4Hub(CORE_HUB).getAssetDeficitRay(WETH_ASSET_ID), 0);
    }

    function test_depositAaveV4_usdc() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        assertEq(usdc.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),  0);
        assertEq(usdc.balanceOf(address(almProxy)),                 USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(CORE_HUB),                          startingHubBalanceUsdc);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.allowance(address(almProxy), MAIN_SPOKE), 0);
        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT, 2);
        assertEq(usdc.balanceOf(address(almProxy)),                 0);
        assertEq(usdc.balanceOf(CORE_HUB),                          startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_weth() external {
        // WETH share price is above 1:1 (accrued interest).
        assertGt(IAaveV4Hub(CORE_HUB).getAddedAssets(WETH_ASSET_ID), IAaveV4Hub(CORE_HUB).getAddedShares(WETH_ASSET_ID));

        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        assertEq(weth.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID),  0);
        assertEq(weth.balanceOf(address(almProxy)),                 WETH_DEPOSIT_AMOUNT);
        assertEq(weth.balanceOf(CORE_HUB),                          startingHubBalanceWeth);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey), WETH_DEPOSIT_LIMIT);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weth.allowance(address(almProxy), MAIN_SPOKE), 0);
        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID), WETH_DEPOSIT_AMOUNT, 10);
        assertEq(weth.balanceOf(address(almProxy)),                 0);
        assertEq(weth.balanceOf(CORE_HUB),                          startingHubBalanceWeth + WETH_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey), WETH_DEPOSIT_LIMIT - WETH_DEPOSIT_AMOUNT);
    }

}

// NOTE: Only testing USDC for non-rate-limit failures as the revert path is asset-agnostic.

contract MainnetController_AaveV4_Withdraw_Tests is AaveV4_TestBase {

    function test_withdrawAaveV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_withdrawAaveV4_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);
    }

    function test_withdrawAaveV4_zeroMaxAmount() external {
        // Longer setup because the rate limit revert is at the end of the function.
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcWithdrawKey, 0, 0);

        deal(Ethereum.USDC, address(almProxy), 1_000e6);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1_000e6);
        vm.stopPrank();
    }

    // Withdrawals are globally unlimited, so a finite withdraw limit is installed locally.
    function test_withdrawAaveV4_usdcRateLimitedBoundary() external {
        uint256 withdrawLimit = 500_000e6;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcWithdrawKey, withdrawLimit, withdrawLimit / 1 days);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, withdrawLimit + 1);

        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, withdrawLimit);
        vm.stopPrank();

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), 0);
    }

    function test_withdrawAaveV4_wethRateLimitedBoundary() external {
        uint256 withdrawLimit = 50e18;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainWethWithdrawKey, withdrawLimit, withdrawLimit / 1 days);

        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, withdrawLimit + 1);

        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, withdrawLimit);
        vm.stopPrank();

        assertApproxEqAbs(rateLimits.getCurrentRateLimit(mainWethWithdrawKey), 0, 10);
    }

    function test_withdrawAaveV4_usdc() external {
        // Gentler slope than the default so the 1 hour deposit-limit refill is partial and observable.
        uint256 depositSlope = uint256(5_000_000e6) / 1 days;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, USDC_DEPOSIT_LIMIT, depositSlope);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        skip(1 hours);

        // The supplied position accrued interest, so it now exceeds the deposit.
        uint256 supplied = _suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID);
        assertGt(supplied, USDC_DEPOSIT_AMOUNT);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CORE_HUB),          startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT + depositSlope * 1 hours);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), type(uint256).max);

        uint256 partialAmount = 400_000e6;

        vm.record();

        // Partial withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, partialAmount);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, partialAmount), partialAmount);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.balanceOf(address(almProxy)),                   partialAmount);
        assertEq(usdc.balanceOf(CORE_HUB),                            startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT - partialAmount);
        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), supplied - partialAmount, 2);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT + depositSlope * 1 hours + partialAmount);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), type(uint256).max);

        // Withdraw all, including the accrued interest
        uint256 remaining = _suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID);

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, remaining);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, type(uint256).max), remaining);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), 0);
        assertApproxEqAbs(usdc.balanceOf(address(almProxy)), supplied, 2);

        // Deposit capacity restored up to the cap; withdraw capacity untouched (unlimited).
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), type(uint256).max);

        // Interest was paid out of the Hub's other liquidity, reducing its cash below the start.
        assertLt(usdc.balanceOf(CORE_HUB), startingHubBalanceUsdc);
    }

    function test_withdrawAaveV4_usdc_zeroDepositRateLimit() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT);

        // Partial withdraw restores deposit capacity
        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 400_000e6), 400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT + 400_000e6);

        // Zero deposit rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), 0);

        // Partial withdraw; the deposit restore is skipped
        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 400_000e6), 400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  0);  // Stays at 0
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), type(uint256).max);
    }

    function test_withdrawAaveV4_weth() external {
        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        skip(1 hours);

        // The supplied position accrued interest, so it now exceeds the deposit.
        uint256 supplied = _suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID);
        assertGt(supplied, WETH_DEPOSIT_AMOUNT);

        assertEq(weth.balanceOf(address(almProxy)),                   0);
        assertEq(weth.balanceOf(CORE_HUB),                            startingHubBalanceWeth + WETH_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  WETH_DEPOSIT_LIMIT);  // Refill capped at max
        assertEq(rateLimits.getCurrentRateLimit(mainWethWithdrawKey), type(uint256).max);

        // Withdraw all, including the accrued interest
        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, supplied);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, type(uint256).max), supplied);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID), 0);
        assertApproxEqAbs(weth.balanceOf(address(almProxy)), supplied, 10);

        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  WETH_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethWithdrawKey), type(uint256).max);

        // Interest was paid out of the Hub's other liquidity, reducing its cash below the start.
        assertLt(weth.balanceOf(CORE_HUB), startingHubBalanceWeth);
    }

}

contract MainnetController_AaveV4_DonationInflationAttack_Test is AaveV4_TestBase {

    // Aave v3 lets an attacker inflate the share price by donating underlying to the aToken, whose
    // accounting derives from balanceOf. Aave v4's Hub tracks liquidity internally, so a raw donation
    // is inert and an honest deposit still receives fair value.
    function test_depositAaveV4_donationDoesNotInflateSharePrice() external {
        IAaveV4Hub hub = IAaveV4Hub(CORE_HUB);

        uint256 liquidityBefore = hub.getAssetLiquidity(USDC_ASSET_ID);
        uint256 assetsBefore    = hub.getAddedAssets(USDC_ASSET_ID);
        uint256 sharesBefore    = hub.getAddedShares(USDC_ASSET_ID);

        // Donate underlying straight to the Hub (the v3 inflation vector).
        uint256 donation = 1_000_000e6;
        deal(Ethereum.USDC, address(this), donation);
        usdc.transfer(CORE_HUB, donation);

        // Raw balance grew, but the Hub's internal accounting is untouched.
        assertEq(usdc.balanceOf(CORE_HUB),             startingHubBalanceUsdc + donation);
        assertEq(hub.getAssetLiquidity(USDC_ASSET_ID), liquidityBefore);
        assertEq(hub.getAddedAssets(USDC_ASSET_ID),    assetsBefore);
        assertEq(hub.getAddedShares(USDC_ASSET_ID),    sharesBefore);

        // Honest deposit still receives fair value (~1:1 net of rounding).
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT, 2);

        // Shares were minted against the deposit, proving the donation did not move the share price.
        assertGt(hub.getAddedShares(USDC_ASSET_ID), sharesBefore);
    }

}

contract MainnetController_AaveV4_TwoSpoke_Tests is AaveV4_TestBase {

    // The same underlying (USDC) supplied through two spokes (Main and Forex, both mapping to Core Hub
    // assetId 5) must have fully independent controller rate limits, since limits are keyed per
    // (spoke, reserveId). Amounts are kept small to stay within each spoke's own Aave add cap.
    function test_aaveV4_twoSpokeRateLimitIsolation() external {
        uint256 amount = 300_000e6;

        deal(Ethereum.USDC, address(almProxy), 2 * amount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT);

        // Main Spoke deposit consumes only Main Spoke capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, amount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - amount);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT);

        // Forex Spoke deposit consumes only Forex Spoke capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, amount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - amount);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT - amount);

        // Positions are tracked separately per spoke.
        assertApproxEqAbs(_suppliedAssets(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID),  amount, 2);
        assertApproxEqAbs(_suppliedAssets(FOREX_SPOKE, FOREX_USDC_RESERVE_ID), amount, 2);

        // Withdrawing from the Main Spoke restores only Main Spoke deposit capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, type(uint256).max);

        assertApproxEqAbs(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT, 2);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT - amount);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),   0);
    }

    // End-to-end flow across three markets on two spokes, interleaving successful and failing
    // deposits/withdrawals. Capacity moves fully independently per (spoke, reserveId), and a withdraw
    // only restores the deposit capacity of the exact market withdrawn. Over-limit deposits revert at
    // the rate-limit check (before the Aave supply call), so they never consume add-cap headroom.
    function test_aaveV4_multiMarketInterleavedScenario() external {
        uint256 usdcLimit = 400_000e6;
        uint256 wethLimit = 200e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey,  usdcLimit, usdcLimit / 1 days);
        rateLimits.setRateLimitData(mainWethDepositKey,  wethLimit, wethLimit / 1 days);
        rateLimits.setRateLimitData(forexUsdcDepositKey, usdcLimit, usdcLimit / 1 days);
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        deal(Ethereum.WETH, address(almProxy), 100e18);

        // Stage 1: Main USDC deposit consumes Main USDC capacity only.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  200_000e6);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  wethLimit);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), usdcLimit);

        // Stage 2: Main WETH deposit consumes Main WETH capacity only.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, 100e18);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  200_000e6);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  100e18);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), usdcLimit);

        // Stage 3: Forex USDC deposit consumes Forex USDC capacity only (same asset, other spoke).
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  200_000e6);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), 200_000e6);

        // Stage 4: Main USDC deposit above its remaining limit reverts and mutates nothing.
        vm.prank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 200_000e6 + 1);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  200_000e6);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), 200_000e6);

        // Stage 5: Forex USDC exhausted, yet Main USDC still works: one market does not freeze another.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), 0);

        vm.prank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_deposit(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  0);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), 0);

        // Stage 6: withdrawing Forex USDC restores Forex capacity only; Main USDC/WETH unchanged.
        vm.prank(allocator);
        mainnetController.aaveV4_withdraw(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 150_000e6);

        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), 150_000e6);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  0);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  100e18);

        // Stage 7: full Main WETH withdraw restores Main WETH capacity only.
        vm.prank(allocator);
        uint256 wethWithdrawn = mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, type(uint256).max);
        assertApproxEqAbs(wethWithdrawn, 100e18, 10);

        assertApproxEqAbs(rateLimits.getCurrentRateLimit(mainWethDepositKey), wethLimit, 10);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), 0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID),  0);

        // Withdraw limits were never consumed by any of the above (still unlimited).
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey),  type(uint256).max);
        assertEq(rateLimits.getCurrentRateLimit(mainWethWithdrawKey),  type(uint256).max);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcWithdrawKey), type(uint256).max);
    }

}
