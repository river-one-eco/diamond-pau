// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC20Mock }       from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

import { ForkTestBase } from"./ForkTestBase.t.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

interface IPSM3Like {

    function setPocket(address pocket) external;

    function shares(address account) external view returns (uint256);

    function totalShares() external view returns (uint256);

    function totalAssets() external view returns (uint256);

}

abstract contract PSM_TestBase is ForkTestBase {

    IERC20Like internal constant USDC = IERC20Like(Base.USDC);

    IERC20Like internal usds;
    IERC20Like internal susds;

    IPSM3Like internal psm;

    address internal pocket = makeAddr("pocket");

    function setUp() public override {
        super.setUp();

        usds  = IERC20Like(address(new ERC20Mock()));
        susds = IERC20Like(address(new ERC20Mock()));

        deal(address(usds), address(this), 1e18);  // For seeding PSM during deployment

        psm = IPSM3Like(PSM3Deploy.deploy(
            Base.SPARK_EXECUTOR, Base.USDC, address(usds), address(susds), Base.SSR_AUTH_ORACLE
        ));

        vm.prank(Base.SPARK_EXECUTOR);
        psm.setPocket(pocket);

        vm.prank(pocket);
        USDC.approve(address(psm), type(uint256).max);

        vm.startPrank(Base.SPARK_EXECUTOR);

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;
        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;

        bytes32 depositKey  = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 withdrawKey = foreignController.LIMIT_PSM_WITHDRAW();

        rateLimits.setRateLimitData(makeAddressKey(depositKey,  Base.USDC),      usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(makeAddressKey(withdrawKey, Base.USDC),      usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(makeAddressKey(depositKey,  address(usds)),  usdsMaxAmount, usdsSlope);
        rateLimits.setRateLimitData(makeAddressKey(depositKey,  address(susds)), usdsMaxAmount, usdsSlope);

        rateLimits.setUnlimitedRateLimitData(makeAddressKey(withdrawKey, address(usds)));
        rateLimits.setUnlimitedRateLimitData(makeAddressKey(withdrawKey, address(susds)));

        foreignController.setPSM3(address(psm));

        vm.stopPrank();
    }

    function _assertState(
        address token,
        uint256 proxyBalance,
        uint256 psmBalance,
        uint256 proxyShares,
        uint256 totalShares,
        uint256 totalAssets,
        bytes32 rateLimitKey,
        uint256 currentRateLimit
    )
        internal
        view
    {
        address custodian = token == Base.USDC ? pocket : address(psm);

        assertEq(IERC20Like(token).balanceOf(almProxy),                   proxyBalance);
        assertEq(IERC20Like(token).balanceOf(address(foreignController)), 0);  // Should always be zero
        assertEq(IERC20Like(token).balanceOf(custodian),                  psmBalance);

        assertEq(psm.shares(almProxy), proxyShares);
        assertEq(psm.totalShares(),    totalShares);
        assertEq(psm.totalAssets(),    totalAssets);

        bytes32 assetKey = makeAddressKey(rateLimitKey, token);

        assertEq(rateLimits.getCurrentRateLimit(assetKey), currentRateLimit);

        // Should always be 0 before and after calls
        assertEq(usds.allowance(almProxy, address(psm)), 0);
    }

}

contract ForeignController_PSM_Deposit_Tests is PSM_TestBase {

    function test_depositPSM_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.depositPSM(address(usds), 1_000_000e18);
    }

    function test_depositPSM_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.depositPSM(address(usds), 1_000_000e18);
    }

    function test_depositPSM_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.depositPSM(makeAddr("fake-token"), 1_000_000e18);
    }

    function test_depositPSM_usdcRateLimitedBoundary() external {
        deal(Base.USDC, almProxy, 5_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.depositPSM(Base.USDC, 5_000_000e6 + 1);

        vm.prank(RELAYER);
        foreignController.depositPSM(Base.USDC, 5_000_000e6);
    }

    function test_depositPSM_usdsRateLimitedBoundary() external {
        deal(address(usds), almProxy, 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.depositPSM(address(usds), 5_000_000e18 + 1);

        vm.prank(RELAYER);
        foreignController.depositPSM(address(usds), 5_000_000e18);
    }

    function test_depositPSM_susdsRateLimitedBoundary() external {
        deal(address(susds), almProxy, 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.depositPSM(address(susds), 5_000_000e18 + 1);

        vm.prank(RELAYER);
        foreignController.depositPSM(address(susds), 5_000_000e18);
    }

    function test_depositPSM_depositUSDS() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(address(usds), almProxy, 100e18);

        _assertState({
            token            : address(usds),
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 shares = foreignController.depositPSM(address(usds), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100e18);

        _assertState({
            token            : address(usds),
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

    function test_depositPSM_depositUSDC() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(Base.USDC, almProxy, 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 shares = foreignController.depositPSM(Base.USDC, 100e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100e18);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_depositPSM_depositSUSDS() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(address(susds), almProxy, 100e18);

        _assertState({
            token            : address(susds),
            proxyBalance     : 100e18,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 shares = foreignController.depositPSM(address(susds), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : address(susds),
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

}

contract ForeignController_PSM_Withdraw_Tests is PSM_TestBase {

    function test_withdrawPSM_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.withdrawPSM(address(usds), 100e18);
    }

    function test_withdrawPSM_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.withdrawPSM(address(usds), 100e18);
    }

    function test_withdrawPSM_usdcZeroMaxAmount() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), Base.USDC);

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.withdrawPSM(Base.USDC, 100e18);
    }

    function test_withdrawPSM_usdsZeroMaxAmount() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), address(usds));

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.withdrawPSM(address(usds), 100e18);
    }

    function test_withdrawPSM_susdsZeroMaxAmount() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), address(susds));

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.withdrawPSM(address(susds), 100e18);
    }

    function test_withdrawPSM_usdcRateLimitedBoundary() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), Base.USDC);

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Base.USDC, almProxy, 1_000_000e6 + 1);

        vm.startPrank(RELAYER);

        foreignController.depositPSM(Base.USDC, 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(Base.USDC, 1_000_000e6 + 1);

        foreignController.withdrawPSM(Base.USDC, 1_000_000e6);

        vm.stopPrank();
    }

    function test_withdrawPSM_usdsRateLimitedBoundary() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), address(usds));

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usds), almProxy, 1_000_000e18 + 1);

        vm.startPrank(RELAYER);

        foreignController.depositPSM(address(usds), 1_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(usds), 1_000_000e18 + 1);

        foreignController.withdrawPSM(address(usds), 1_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawPSM_susdsRateLimitedBoundary() external {
        bytes32 withdrawAssetKey = makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), address(susds));

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        // NOTE: Need an extra wei because of rounding on conversion
        deal(address(susds), almProxy, 1_000_000e18 + 2);

        vm.startPrank(RELAYER);

        foreignController.depositPSM(address(susds), 1_000_000e18 + 2);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(susds), 1_000_000e18 + 1);

        uint256 withdrawn = foreignController.withdrawPSM(address(susds), 1_000_000e18);

        assertEq(withdrawn, 1_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawPSM_withdrawUSDS() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(address(usds), almProxy, 100e18);
        vm.prank(RELAYER);
        foreignController.depositPSM(address(usds), 100e18);

        _assertState({
            token            : address(usds),
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(usds), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e18);

        _assertState({
            token            : address(usds),
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

    function test_withdrawPSM_withdrawUSDC() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(Base.USDC, almProxy, 100e6);

        vm.prank(RELAYER);
        foreignController.depositPSM(Base.USDC, 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 amountWithdrawn = foreignController.withdrawPSM(Base.USDC, 100e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_withdrawPSM_withdrawSUSDS() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(address(susds), almProxy, 100e18);

        vm.prank(RELAYER);
        uint256 shares = foreignController.depositPSM(address(susds), 100e18);

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : address(susds),
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.record();

        vm.prank(RELAYER);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(susds), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e18 - 1);  // Rounding

        _assertState({
            token            : address(susds),
            proxyBalance     : 100e18 - 1,  // Rounding
            psmBalance       : 1,           // Rounding
            proxyShares      : 0,
            totalShares      : 1e18,      // From seeding USDS
            totalAssets      : 1e18 + 1,  // From seeding USDS, rounding
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

}
