// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Id, MarketParams, MarketParamsLib }  from "../../../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import { ReentrancyGuard } from "../../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../../../lib/spark-address-registry/src/Ethereum.sol";

import { IERC4626Facet } from "../IERC4626Facet.sol";

import { MainnetTests } from "../../../../test/fork/Mainnet.t.sol";

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

interface IMetaMorphoLike {

    function acceptCap(MarketParams memory marketParams) external;

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function setCurator(address newCurator) external;

    function setFeeRecipient(address newFeeRecipient) external;

    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    function setSkimRecipient(address newSkimRecipient) external;

    function setSupplyQueue(Id[] calldata newSupplyQueue) external;

    function submitCap(MarketParams memory marketParams, uint256 newSupplyCap) external;

    function submitGuardian(address newGuardian) external;

    function MORPHO() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function curator() external view returns (address);

    function feeRecipient() external view returns (address);

    function guardian() external view returns (address);

    function isAllocator(address target) external view returns (bool);

    function symbol() external view returns (string memory);

    function timelock() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IMorphoLike {

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    function market(Id id) external view returns (Market memory m);

}

abstract contract Mainnet_ERC4626_SUSDS_Tests is MainnetTests {

    uint256 internal SUSDS_CONVERTED_ASSETS;
    uint256 internal SUSDS_CONVERTED_SHARES;

    uint256 internal SUSDS_TOTAL_ASSETS;
    uint256 internal SUSDS_TOTAL_SUPPLY;

    uint256 internal SUSDS_DRIP_AMOUNT;

    bytes32 internal depositKey;
    bytes32 internal withdrawKey;

    function setUp() public override {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.usds_setVault(vault);

        depositKey  = mainnetController.erc4626_getDepositRateLimitKey(Ethereum.SUSDS, Ethereum.USDS);
        withdrawKey = mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.usds_mintRateLimitKey(), 10_000_000e18, uint256(10_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.erc4626_setMaxExchangeRate(address(susds), susds.convertToShares(1e18), 1.2e18);
        vm.stopPrank();

        SUSDS_CONVERTED_ASSETS = susds.convertToAssets(1e18);
        SUSDS_CONVERTED_SHARES = susds.convertToShares(1e18);

        SUSDS_TOTAL_ASSETS = susds.totalAssets();
        SUSDS_TOTAL_SUPPLY = susds.totalSupply();

        // Setting this value directly because susds.drip() fails in setUp with
        // StateChangeDuringStaticCall and it is unclear why, something related to foundry.
        SUSDS_DRIP_AMOUNT = 849.454677397481388011e18;

        assertEq(SUSDS_CONVERTED_ASSETS, 1.003430776383974596e18);
        assertEq(SUSDS_CONVERTED_SHARES, 0.996580953599671364e18);

        assertEq(SUSDS_TOTAL_ASSETS, 485_597_342.757158870618550128e18);
        assertEq(SUSDS_TOTAL_SUPPLY, 483_937_062.910395855928183397e18);
    }

}

contract Mainnet_ERC4626_Deposit_Tests is Mainnet_ERC4626_SUSDS_Tests {

    function test_depositERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc4626_deposit(address(susds), 1e18, 0);
    }

    function test_depositERC4626_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc4626_deposit(address(susds), 1e18, 0);
    }

    function test_depositERC4626_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1e18, 0);
    }

    function test_depositERC4626_rateLimitBoundary() external {
        vm.startPrank(allocator);

        mainnetController.usds_mint(5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.erc4626_deposit(address(susds), 5_000_000e18 + 1, 0);

        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, 0);

        vm.stopPrank();
    }

    function test_depositERC4626_exchangeRateBoundary() external {
        vm.prank(allocator);
        mainnetController.usds_mint(5_000_000e18);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.erc4626_setMaxExchangeRate(
            address(susds),
            susds.convertToShares(5_000_000e18),
            5_000_000e18 - 1
        );
        vm.stopPrank();

        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.erc4626_setMaxExchangeRate(
            address(susds),
            susds.convertToShares(5_000_000e18),
            5_000_000e18
        );
        vm.stopPrank();

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, 0);
    }

    function test_depositERC4626_zeroExchangeRate() external {
        vm.prank(allocator);
        mainnetController.usds_mint(5_000_000e18);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.erc4626_setMaxExchangeRate(address(susds), 0, 0);

        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, 0);
    }

    function test_depositERC4626_minSharesOutNotMetBoundary() external {
        uint256 overBoundaryShares = susds.convertToShares(5_000_000e18) + 1;
        uint256 atBoundaryShares   = susds.convertToShares(5_000_000e18);

        vm.startPrank(allocator);

        mainnetController.usds_mint(5_000_000e18);

        vm.expectRevert("ERC4626Facet/min-shares-out-not-met");
        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, overBoundaryShares);

        mainnetController.erc4626_deposit(address(susds), 5_000_000e18, atBoundaryShares);

        vm.stopPrank();
    }

    function test_depositERC4626() external {
        vm.prank(allocator);
        mainnetController.usds_mint(2e18);

        assertEq(usds.balanceOf(address(almProxy)),          2e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)), 0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IERC4626Facet.ERC4626Deposit(address(susds), 1e18, SUSDS_CONVERTED_SHARES);

        vm.prank(allocator);
        uint256 shares = mainnetController.erc4626_deposit(
            address(susds),
            1e18,
            SUSDS_CONVERTED_SHARES
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)), 0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + shares);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);
    }

}

contract Mainnet_ERC4626_Withdraw_Tests is Mainnet_ERC4626_SUSDS_Tests {

    function test_withdrawERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc4626_withdraw(address(susds), 1e18, 1e18);
    }

    function test_withdrawERC4626_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc4626_withdraw(address(susds), 1e18, 1e18);
    }

    function test_withdrawERC4626_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS),
            0,
            0
        );
        vm.stopPrank();

        vm.startPrank(allocator);
        mainnetController.usds_mint(100e18);
        mainnetController.erc4626_deposit(address(susds), 100e18, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc4626_withdraw(address(susds), 1e18, 1e18);
    }

    function test_withdrawERC4626_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);

        vm.startPrank(allocator);

        mainnetController.usds_mint(10_000_000e18);
        mainnetController.erc4626_deposit(address(susds), 10_000_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.erc4626_withdraw(address(susds), 5_000_000e18 + 1, 5_000_000e18 + 1);

        mainnetController.erc4626_withdraw(address(susds), 5_000_000e18, 5_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawERC4626_maxSharesInNotMetBoundary() external {
        uint256 underBoundaryShares = susds.previewWithdraw(1_000_000e18) - 1;
        uint256 atBoundaryShares    = susds.previewWithdraw(1_000_000e18);

        vm.startPrank(allocator);

        mainnetController.usds_mint(2_000_000e18);
        mainnetController.erc4626_deposit(address(susds), 2_000_000e18, 0);

        vm.expectRevert("ERC4626Facet/shares-burned-too-high");
        mainnetController.erc4626_withdraw(address(susds), 1_000_000e18, underBoundaryShares);

        mainnetController.erc4626_withdraw(address(susds), 1_000_000e18, atBoundaryShares);

        vm.stopPrank();
    }

    function test_withdrawERC4626() external {
        vm.prank(allocator);
        mainnetController.usds_mint(2e18);

        vm.expectEmit(address(mainnetController));
        emit IERC4626Facet.ERC4626Deposit({
            token  : address(susds),
            assets : 1e18,
            shares : SUSDS_CONVERTED_SHARES
        });

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1e18, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + SUSDS_CONVERTED_SHARES);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IERC4626Facet.ERC4626Withdraw(address(susds), 1e18 - 1, SUSDS_CONVERTED_SHARES);

        // Max available with rounding
        vm.prank(allocator);
        uint256 shares = mainnetController.erc4626_withdraw(
            address(susds),
            1e18 - 1,
            SUSDS_CONVERTED_SHARES
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(shares, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          2e18 - 1);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1);  // Rounding

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);
    }

    function test_withdrawERC4626_zeroDepositRateLimit() external {
        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1_000_000e18, 990_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        // Partial withdraw
        vm.prank(allocator);
        mainnetController.erc4626_withdraw(address(susds), 400_000e18, 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_400_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 4_600_000e18);

        // Zero deposit rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  0);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 4_600_000e18);

        // Partial withdraw
        vm.prank(allocator);
        mainnetController.erc4626_withdraw(address(susds), 400_000e18, 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  0);  // stays at 0
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 4_200_000e18);
    }

}

contract Mainnet_ERC4626_Redeem_Tests is Mainnet_ERC4626_SUSDS_Tests {

    function test_redeemERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc4626_redeem(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc4626_redeem(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS),
            0,
            0
        );
        vm.stopPrank();

        vm.startPrank(allocator);
        mainnetController.usds_mint(100e18);
        mainnetController.erc4626_deposit(address(susds), 100e18, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc4626_redeem(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);

        vm.startPrank(allocator);

        mainnetController.usds_mint(10_000_000e18);
        mainnetController.erc4626_deposit(address(susds), 10_000_000e18, 0);

        uint256 overBoundaryShares = susds.convertToShares(5_000_000e18 + 2);
        uint256 atBoundaryShares   = susds.convertToShares(5_000_000e18 + 1);  // Still rounds down

        assertEq(susds.previewRedeem(overBoundaryShares), 5_000_000e18 + 1);
        assertEq(susds.previewRedeem(atBoundaryShares),   5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.erc4626_redeem(address(susds), overBoundaryShares, 1e18);

        mainnetController.erc4626_redeem(address(susds), atBoundaryShares, 1e18);

        vm.stopPrank();
    }

    function test_redeemERC4626_minAssetsOutNotMetBoundary() external {
        vm.startPrank(allocator);

        mainnetController.usds_mint(2_000_000e18);
        mainnetController.erc4626_deposit(address(susds), 2_000_000e18, 0);

        uint256 shares = susds.convertToShares(2_000_000e18);

        uint256 overBoundaryAssets = susds.convertToAssets(shares) + 1;
        uint256 atBoundaryAssets   = susds.convertToAssets(shares);

        vm.expectRevert("ERC4626Facet/min-assets-out-not-met");
        mainnetController.erc4626_redeem(address(susds), shares, overBoundaryAssets);

        mainnetController.erc4626_redeem(address(susds), shares, atBoundaryAssets);

        vm.stopPrank();
    }

    function test_redeemERC4626() external {
        vm.prank(allocator);
        mainnetController.usds_mint(2e18);

        vm.expectEmit(address(mainnetController));
        emit IERC4626Facet.ERC4626Deposit({
            token  : address(susds),
            assets : 1e18,
            shares : SUSDS_CONVERTED_SHARES
        });

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1e18, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + SUSDS_CONVERTED_SHARES);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IERC4626Facet.ERC4626Redeem(address(susds), SUSDS_CONVERTED_SHARES, 1e18 - 1);

        vm.prank(allocator);
        uint256 assets = mainnetController.erc4626_redeem(
            address(susds),
            SUSDS_CONVERTED_SHARES,
            1e18 - 1 // Rounding
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(assets, 1e18 - 1);  // Rounding

        assertEq(usds.balanceOf(address(almProxy)),          2e18 - 1);  // Rounding
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1);  // Rounding

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)), 0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);
    }

    function test_redeemERC4626_zeroDepositRateLimit() external {
        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1_000_000e18, 990_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        uint256 assets1 = susds.convertToAssets(400_000e18);

        // Partial redeem
        vm.prank(allocator);
        mainnetController.erc4626_redeem(address(susds), 400_000e18, 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_000_000e18 + assets1);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - assets1);

        // Zero deposit rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  0);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - assets1);

        uint256 assets2 = susds.convertToAssets(400_000e18);

        // Partial redeem
        vm.prank(allocator);
        mainnetController.erc4626_redeem(address(susds), 400_000e18, 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  0);  // stays at 0
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - assets1 - assets2);
    }

}

contract Mainnet_ERC4626_Attack_Tests is Mainnet_ERC4626_SUSDS_Tests {

    function test_attack_assetChanged_depositERC4626() external {
        assertEq(rateLimits.getCurrentRateLimit(depositKey), 5_000_000e18);

        // Deposit succeeds with the original underlying (USDS).
        vm.startPrank(allocator);
        mainnetController.usds_mint(1_000_000e18);
        mainnetController.erc4626_deposit(address(susds), 1_000_000e18, 0);
        vm.stopPrank();

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 4_000_000e18);

        // Attack: mock asset() to return a different address
        address changedAsset = Ethereum.DAI;
        vm.mockCall(
            address(susds),
            abi.encodeWithSignature("asset()"),
            abi.encode(changedAsset)
        );

        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        // Cannot deposit with the changed asset
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(susds), 1_000_000e18, 0);
    }

}

contract Mainnet_ERC4626_DonationAttack_Tests is MainnetTests {

    IMetaMorphoLike internal constant MORPHO_VAULT = IMetaMorphoLike(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    address internal morpho;

    MarketParams internal marketParams = MarketParams({
        loanToken       : Ethereum.USDS,
        collateralToken : address(0x0),
        oracle          : address(0x0),
        irm             : address(0x0),
        lltv            : 0
    });

    Id internal marketId = MarketParamsLib.id(marketParams);

    address internal attacker        = makeAddr("attacker");
    address internal curator         = makeAddr("curator");
    address internal feeRecipient    = makeAddr("feeRecipient");
    address internal guardian        = makeAddr("guardian");
    address internal morphoAllocator = makeAddr("morphoAllocator");
    address internal skimRecipient   = makeAddr("skimRecipient");

    function setUp() public override {
        super.setUp();

        morpho = MORPHO_VAULT.MORPHO();

        bytes32 depositKey  = mainnetController.erc4626_getDepositRateLimitKey(address(MORPHO_VAULT), Ethereum.USDS);
        bytes32 withdrawKey = mainnetController.erc4626_getWithdrawRateLimitKey(address(MORPHO_VAULT));

        // Basic validation
        assertEq(keccak256(abi.encode(MORPHO_VAULT.symbol())), keccak256(abi.encode("sparkUSDS")));
        assertEq(MORPHO_VAULT.totalAssets(),                   0);
        assertEq(MORPHO_VAULT.totalSupply(),                   0);

        // Initialization
        vm.startPrank(Ethereum.SPARK_PROXY);

        MORPHO_VAULT.setCurator(curator);
        MORPHO_VAULT.submitGuardian(guardian);
        MORPHO_VAULT.setFeeRecipient(feeRecipient);
        MORPHO_VAULT.setIsAllocator(morphoAllocator, true);
        MORPHO_VAULT.setSkimRecipient(skimRecipient);

        MORPHO_VAULT.submitCap(marketParams, 10_000_000e18);
        skip(MORPHO_VAULT.timelock());  // Wait the timelock
        MORPHO_VAULT.acceptCap(marketParams);

        // Now that the market has a non-zero cap, set the supply queue order
        Id[] memory supplyOrder = new Id[](1);
        supplyOrder[0] = marketId;
        MORPHO_VAULT.setSupplyQueue(supplyOrder);

        vm.stopPrank();

        assertEq(MORPHO_VAULT.curator(),      curator);
        assertEq(MORPHO_VAULT.guardian(),     guardian);
        assertEq(MORPHO_VAULT.feeRecipient(), feeRecipient);

        assertTrue(MORPHO_VAULT.isAllocator(morphoAllocator));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22932160;  // July 16, 2025
    }

    function test_depositERC4626_donationAttackFailure() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.erc4626_setMaxExchangeRate(address(MORPHO_VAULT), 1e18, 10e18);
        vm.stopPrank();

        _doAttack();

        vm.prank(allocator);
        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        mainnetController.erc4626_deposit(address(MORPHO_VAULT), 2_000_000e18, 0);
    }

    function test_depositERC4626_donationAttackSuccess() external {
        // Set max exchange rate too high
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.erc4626_setMaxExchangeRate(address(MORPHO_VAULT), 1, MORPHO_VAULT.convertToAssets(1e24));
        vm.stopPrank();

        _doAttack();

        vm.prank(allocator);
        uint256 shares = mainnetController.erc4626_deposit(address(MORPHO_VAULT), 2_000_000e18, 0);

        // One can compute:
        // shares == assets * (totalSupply + 1) / (totalAssets + 1)
        //        == 2_000_000e18 * (1 + 1) / (1_000_000e18 + 1 + 1)
        //        == 3.9..
        // Rounding down, the proxy receives 3 shares.
        assertEq(shares,                    3);
        assertEq(MORPHO_VAULT.totalAssets(), 3_000_000e18 + 1);
        assertEq(MORPHO_VAULT.totalSupply(), 4);

        uint256 assetsOfProxy    = MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(address(almProxy)));
        uint256 assetsOfAttacker = MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(attacker));

        // convertToAssets(shares) == shares * (totalAssets + 1) / (totalSupply + 1)
        // convertToAssets(3)      == 3 * (3_000_000e18 + 1 + 1) / (4 + 1)
        //                         == 1_800_000e18 + 1
        assertEq(assetsOfProxy, 1_800_000e18 + 1);
        assertLt(assetsOfProxy, 2_000_000e18);  // The proxy owns less than it deposited
        // convertToAssets(1)      == 1 * (3_000_000e18 + 1 + 1) / (4 + 1)
        //                         == 600_000e18
        assertEq(assetsOfAttacker, 600_000e18);
    }

    function _doAttack() internal {
        Market memory market = IMorphoLike(morpho).market(marketId);

        assertEq(market.totalSupplyAssets, 36_095_481.319542091092211965e18); // ~36M USDS
        assertEq(market.totalSupplyShares, 36_095_481.319542091092211965000000e24);

        deal(address(usds), attacker, 1_000_000e18 + 1);

        vm.startPrank(attacker);

        usds.approve(address(MORPHO_VAULT), 1);
        MORPHO_VAULT.deposit(1, attacker);
        usds.approve(morpho, 1_000_000e18);

        // Donation attack performed by donating shares of Morpho market supply to Morpho vault
        ( uint256 assets, uint256 shares ) = IMorphoLike(morpho).supply(
            marketParams, 1_000_000e18, 0, address(MORPHO_VAULT), hex""
        );

        vm.stopPrank();

        assertEq(assets, 1_000_000e18);
        assertEq(shares, uint256(1_000_000e18) * market.totalSupplyShares / market.totalSupplyAssets);
        assertEq(shares, 1e30);

        assertEq(MORPHO_VAULT.balanceOf(attacker), 1);
        assertEq(MORPHO_VAULT.totalSupply(),       1);

        assertEq(MORPHO_VAULT.totalAssets(), 1_000_000e18 + 1);
        // Instead of performing shares * totalAssets / totalShares, aka
        // 1 * (1_000_000e18 + 1) / 1 == 1_000_000e18 + 1, the vault actually adds 1 to the
        // numerator and denominator, so one gets 1 * (1_000_000e18 + 1 + 1) / (1 + 1)
        // == (1_000_000e18 + 2) / 2 == 500_000e18 + 1.
        assertEq(MORPHO_VAULT.convertToAssets(1), 500_000e18 + 1);

        deal(address(usds), address(almProxy), 2_000_000e18);
    }

}
