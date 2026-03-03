// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Avalanche } from "../../lib/grove-address-registry/src/Avalanche.sol";

import { makeAddressKey, makeAddressUint16Key } from "../../src/RateLimitHelpers.sol";

import {
    IAsyncRedeemManagerLike,
    IBalanceSheetLike,
    ICentrifugeV3ShareLike,
    ICentrifugeV3VaultLike,
    IFreelyTransferableHookLike,
    ISpokeLike
} from "../interfaces/Centrifuge.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

abstract contract Centrifuge_TestBase is ForkTestBase {

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    IERC20Like internal constant USDC = IERC20Like(Avalanche.USDC);

    // deJAAA USDC Vault
    ICentrifugeV3VaultLike internal constant CENTRIFUGE_VAULT = ICentrifugeV3VaultLike(0xCF4C60066aAB54b3f750F94c2a06046d5466Ccf9);

    ICentrifugeV3ShareLike      internal vaultToken;
    IFreelyTransferableHookLike internal vaultTokenHook;
    IAsyncRedeemManagerLike     internal manager;
    IBalanceSheetLike           internal balanceSheet;
    ISpokeLike                  internal spoke;

    address internal globalEscrow;
    address internal poolEscrow;
    address internal root;

    uint64  internal poolId;
    bytes16 internal scId;
    uint128 internal usdcAssetId;

    function setUp() public virtual override {
        super.setUp();

        vaultToken     = ICentrifugeV3ShareLike(CENTRIFUGE_VAULT.share());
        vaultTokenHook = IFreelyTransferableHookLike(vaultToken.hook());
        manager        = IAsyncRedeemManagerLike(CENTRIFUGE_VAULT.manager());
        balanceSheet   = IBalanceSheetLike(manager.balanceSheet());
        spoke          = ISpokeLike(manager.spoke());

        root   = CENTRIFUGE_VAULT.root();
        poolId = CENTRIFUGE_VAULT.poolId();
        scId   = CENTRIFUGE_VAULT.scId();

        usdcAssetId = spoke.assetToId(CENTRIFUGE_VAULT.asset(), 0);

        globalEscrow = manager.globalEscrow();
        poolEscrow   = manager.poolEscrow(poolId);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 65896755;  // July 22, 2025
    }

}

contract ForeignController_Centrifuge_RequestDepositERC7540_Tests is Centrifuge_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Avalanche.USDC, almProxy, 1_000_000e6);
    }

    function test_requestDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6 + 1);

        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(USDC.allowance(almProxy, address(CENTRIFUGE_VAULT)), 0);

        uint256 initialEscrowBal = USDC.balanceOf(globalEscrow);

        assertEq(USDC.balanceOf(almProxy),     1_000_000e6);
        assertEq(USDC.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID, almProxy), 0);

        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(USDC.allowance(almProxy, address(CENTRIFUGE_VAULT)), 0);

        assertEq(USDC.balanceOf(almProxy),     0);
        assertEq(USDC.balanceOf(globalEscrow), initialEscrowBal + 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);
    }

}

contract ForeignController_Centrifuge_ClaimDepositERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_500_000e6, uint256(1_500_000e6) / 1 days);
    }

    function test_claimDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimDepositERC7540(address(CENTRIFUGE_VAULT));
    }

    function test_claimDepositERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Lib/invalid-action");
        vm.prank(RELAYER);
        foreignController.claimDepositERC7540(makeAddr("fake-vault"));
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(Avalanche.USDC, almProxy, 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request deposit into Centrifuge V3 Vault by supplying USDC
        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
        assertEq(vaultToken.balanceOf(almProxy),     0);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Issue shares at price 2.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            500_000e6,
            2e18
        );

        // Fulfill request at price 2.0
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            1_000_000e6,
            500_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply + 500_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + 500_000e6);
        assertEq(vaultToken.balanceOf(almProxy),     0);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);

        // Claim shares
        vm.prank(RELAYER);
        foreignController.claimDepositERC7540(address(CENTRIFUGE_VAULT));

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
        assertEq(vaultToken.balanceOf(almProxy),     500_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);
    }

    function test_claimDepositERC7540_multipleRequests() external {
        deal(Avalanche.USDC, almProxy, 1_500_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request deposit into Centrifuge V3 Vault by supplying USDC
        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
        assertEq(vaultToken.balanceOf(almProxy),     0);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request another deposit into Centrifuge V3 Vault by supplying more USDC
        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 500_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
        assertEq(vaultToken.balanceOf(almProxy),     0);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 1_500_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Issue shares at price 2.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            750_000e6,
            2e18
        );

        // Fulfill both requests at price 2.0
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            1_500_000e6,
            750_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply + 750_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + 750_000e6);
        assertEq(vaultToken.balanceOf(almProxy),     0);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 1_500_000e6);

        // Claim shares
        vm.prank(RELAYER);
        foreignController.claimDepositERC7540(address(CENTRIFUGE_VAULT));

        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
        assertEq(vaultToken.balanceOf(almProxy),     750_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);
    }

}

contract ForeignController_Centrifuge_CancelDepositERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.cancelCentrifugeDepositRequest(address(CENTRIFUGE_VAULT));
    }

    function test_cancelCentrifugeDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        foreignController.cancelCentrifugeDepositRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(Avalanche.USDC, almProxy, 1_000_000e6);

        vm.prank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,       almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy), false);

        vm.prank(RELAYER);
        foreignController.cancelCentrifugeDepositRequest(address(CENTRIFUGE_VAULT));

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,       almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelDeposit_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimCentrifugeCancelDepositRequest(address(CENTRIFUGE_VAULT));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        foreignController.claimCentrifugeCancelDepositRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(Avalanche.USDC, almProxy, 1_000_000e6);

        uint256 initialEscrowBal = USDC.balanceOf(globalEscrow);

        assertEq(USDC.balanceOf(almProxy),     1_000_000e6);
        assertEq(USDC.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        vm.startPrank(RELAYER);
        foreignController.requestDepositERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
        foreignController.cancelCentrifugeDepositRequest(address(CENTRIFUGE_VAULT));
        vm.stopPrank();

        assertEq(USDC.balanceOf(almProxy),     0);
        assertEq(USDC.balanceOf(globalEscrow), initialEscrowBal + 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,         almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID,   almProxy), true);
        assertEq(CENTRIFUGE_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        // Fulfill cancellation request
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            1_000_000e6,
            0,
            1_000_000e6
        );

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);

        vm.prank(RELAYER);
        foreignController.claimCentrifugeCancelDepositRequest(address(CENTRIFUGE_VAULT));

        assertEq(CENTRIFUGE_VAULT.pendingDepositRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelDepositRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        assertEq(USDC.balanceOf(almProxy),     1_000_000e6);
        assertEq(USDC.balanceOf(globalEscrow), initialEscrowBal);
    }

}

contract ForeignController_Centrifuge_RequestRedeemERC7540_Tests is Centrifuge_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);
        spoke.updatePricePoolPerAsset(poolId, scId, usdcAssetId, 1e6, uint64(block.timestamp));
        spoke.updatePricePoolPerShare(poolId, scId, 1e18, uint64(block.timestamp));
        vm.stopPrank();

        key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.prank(root);
        vaultToken.mint(almProxy, 2_000_000e6);

        uint256 overBoundaryShares = CENTRIFUGE_VAULT.convertToShares(1_000_000e6 + 1);
        uint256 atBoundaryShares   = CENTRIFUGE_VAULT.convertToShares(1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), overBoundaryShares);

        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), atBoundaryShares);
    }

    function test_requestRedeemERC7540() external {
        uint256 shares = CENTRIFUGE_VAULT.convertToShares(1_000_000e6);

        vm.prank(root);
        vaultToken.mint(almProxy, shares);

        assertEq(shares, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(almProxy),     shares);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy), 0);

        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);  // Rounding

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + shares);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy), shares);
    }

}

contract ForeignController_Centrifuge_ClaimRedeemERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 2_000_000e6, uint256(2_000_000e6) / 1 days);
    }

    function test_claimRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimRedeemERC7540(address(CENTRIFUGE_VAULT));
    }

    function test_claimRedeemERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Lib/invalid-action");
        vm.prank(RELAYER);
        foreignController.claimRedeemERC7540(makeAddr("fake-vault"));
    }

    function test_claimRedeemERC7540_singleRequest() external {
        vm.prank(root);
        vaultToken.mint(almProxy, 1_000_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(almProxy),     1_000_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request Centrifuge V3 Vault redemption
        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Deposit 2M USDC
        deal(Avalanche.USDC, root, 2_000_000e6);

        vm.startPrank(root);
        USDC.approve(address(balanceSheet), 2_000_000e6);
        balanceSheet.deposit(poolId, scId, Avalanche.USDC, 0, 2_000_000e6);
        vm.stopPrank();

        // Revoke shares at price 2.0
        vm.prank(root);
        manager.revokedShares(
            poolId,
            scId,
            usdcAssetId,
            2_000_000e6,
            1_000_000e6,
            2e18
        );

        // Fulfill request at price 2.0
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            2_000_000e6,
            1_000_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply - 1_000_000e6);

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(USDC.balanceOf(poolEscrow), 2_000_000e6);
        assertEq(USDC.balanceOf(almProxy),   0);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 1_000_000e6);

        // Claim assets
        vm.prank(RELAYER);
        foreignController.claimRedeemERC7540(address(CENTRIFUGE_VAULT));

        assertEq(USDC.balanceOf(poolEscrow), 0);
        assertEq(USDC.balanceOf(almProxy),   2_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);
    }

    function test_claimRedeemERC7540_multipleRequests() external {
        vm.prank(root);
        vaultToken.mint(almProxy, 1_500_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(almProxy),     1_500_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request Centrifuge V3 Vault redemption
        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        assertEq(vaultToken.balanceOf(almProxy),     500_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + 1_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 1_000_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request another Centrifuge V3 Vault redemption
        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), 500_000e6);

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + 1_500_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 1_500_000e6);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Deposit 2M USDC
        deal(Avalanche.USDC, root, 3_000_000e6);

        vm.startPrank(root);
        USDC.approve(address(balanceSheet), 3_000_000e6);
        balanceSheet.deposit(poolId, scId, Avalanche.USDC, 0, 3_000_000e6);
        vm.stopPrank();

        // Revoke shares at price 2.0
        vm.prank(root);
        manager.revokedShares(
            poolId,
            scId,
            usdcAssetId,
            3_000_000e6,
            1_500_000e6,
            2e18
        );

        // Fulfill both requests at price 2.0
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            3_000_000e6,
            1_500_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply - 1_500_000e6);

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(USDC.balanceOf(poolEscrow), 3_000_000e6);
        assertEq(USDC.balanceOf(almProxy),   0);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 1_500_000e6);

        // Claim assets
        vm.prank(RELAYER);
        foreignController.claimRedeemERC7540(address(CENTRIFUGE_VAULT));

        assertEq(USDC.balanceOf(poolEscrow), 0);
        assertEq(USDC.balanceOf(almProxy),   3_000_000e6);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,   almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);
    }

}

contract ForeignController_Centrifuge_CancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.cancelCentrifugeRedeemRequest(address(CENTRIFUGE_VAULT));
    }

    function test_cancelCentrifugeRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        foreignController.cancelCentrifugeRedeemRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = 1_000_000e6;

        vm.prank(root);
        vaultToken.mint(almProxy, 1_000_000e6);

        vm.prank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), shares);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,       almProxy), shares);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy), false);

        vm.prank(RELAYER);
        foreignController.cancelCentrifugeRedeemRequest(address(CENTRIFUGE_VAULT));

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,       almProxy), shares);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(CENTRIFUGE_VAULT)
        );

        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimCentrifugeCancelRedeemRequest(address(CENTRIFUGE_VAULT));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        foreignController.claimCentrifugeCancelRedeemRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelRedeemRequest() external {
        uint256 shares = 1_000_000e6;

        vm.prank(root);
        vaultToken.mint(almProxy, shares);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(almProxy),     shares);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        vm.startPrank(RELAYER);
        foreignController.requestRedeemERC7540(address(CENTRIFUGE_VAULT), shares);
        foreignController.cancelCentrifugeRedeemRequest(address(CENTRIFUGE_VAULT));
        vm.stopPrank();

        assertEq(vaultToken.balanceOf(almProxy),     0);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal + shares);

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,         almProxy), shares);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID,   almProxy), true);
        assertEq(CENTRIFUGE_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        // Fulfill cancellation request
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            almProxy,
            usdcAssetId,
            0,
            0,
            uint128(shares)
        );

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), shares);

        vm.prank(RELAYER);
        foreignController.claimCentrifugeCancelRedeemRequest(address(CENTRIFUGE_VAULT));

        assertEq(CENTRIFUGE_VAULT.pendingRedeemRequest(REQUEST_ID,         almProxy), 0);
        assertEq(CENTRIFUGE_VAULT.pendingCancelRedeemRequest(REQUEST_ID,   almProxy), false);
        assertEq(CENTRIFUGE_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        assertEq(vaultToken.balanceOf(almProxy),     shares);
        assertEq(vaultToken.balanceOf(globalEscrow), initialEscrowBal);
    }

}

contract ForeignController_Centrifuge_TransferShares_Tests is Centrifuge_TestBase {

    uint16 internal constant DESTINATION_CENTRIFUGE_ID = 1; // Mainnet Centrifuge ID

    bytes32 internal key;
    bytes32 internal target;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Avalanche.GROVE_EXECUTOR);

        key = makeAddressUint16Key(
            foreignController.LIMIT_CENTRIFUGE_TRANSFER(),
            address(CENTRIFUGE_VAULT),
            DESTINATION_CENTRIFUGE_ID
        );

        target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), almProxy, 10_000_000e6);
        deal(RELAYER, 1 ether);  // Gas cost for Centrifuge
    }

    function test_transferSharesCentrifuge_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.transferSharesCentrifuge(address(CENTRIFUGE_VAULT), 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.prank(Avalanche.GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        foreignController.transferSharesCentrifuge(address(CENTRIFUGE_VAULT), 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            address(CENTRIFUGE_VAULT),
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            address(CENTRIFUGE_VAULT),
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        vm.prank(Avalanche.GROVE_EXECUTOR);
        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, bytes32(0));

        vm.expectRevert("CentrifugeLib/id-not-configured");
        vm.prank(RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            address(CENTRIFUGE_VAULT),
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge() external {
        // Issue shares at price 1.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            10_000_000e6,
            1e18
        );

        uint256 proxyBalanceBefore     = vaultToken.balanceOf(almProxy);
        uint256 shareTotalSupplyBefore = vaultToken.totalSupply();

        vm.expectEmit(address(spoke));
        emit ISpokeLike.InitiateTransferShares(
            DESTINATION_CENTRIFUGE_ID,
            poolId,
            scId,
            almProxy,
            target,
            10_000_000e6
        );

        vm.prank(RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            address(CENTRIFUGE_VAULT),
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        uint256 proxyBalanceAfter     = vaultToken.balanceOf(almProxy);
        uint256 shareTotalSupplyAfter = vaultToken.totalSupply();

        assertEq(proxyBalanceAfter,     proxyBalanceBefore     - 10_000_000e6);
        assertEq(shareTotalSupplyAfter, shareTotalSupplyBefore - 10_000_000e6);
    }

}
