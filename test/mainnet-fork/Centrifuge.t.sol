// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

import {
    ICentrifugeV3VaultLike,
    IERC20MintableLike,
    IInvestmentManager,
    IRestrictionManager
} from "../interfaces/Centrifuge.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

contract Centrifuge_TestBase is ForkTestBase {

    address internal constant ESCROW = 0x0000000005F458Fd6ba9EEb5f365D83b7dA913dD;
    address internal constant ROOT   = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;

    bytes16 internal constant JTREASURY_TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 internal constant USDC_ASSET_ID        = 242333941209166991950178742833476896417;
    uint64  internal constant JTREASURY_POOL_ID    = 4139607887;

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    IInvestmentManager internal constant INVESTMENT_MANAGER = IInvestmentManager(0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9);

    // JTREASURY_RESTRICTION_MANAGER
    IRestrictionManager internal constant RESTRICTION_MANAGER = IRestrictionManager(0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0);

    // JTREASURY_VAULT_USDC
    ICentrifugeV3VaultLike internal constant TREASURY_VAULT = ICentrifugeV3VaultLike(0x36036fFd9B1C6966ab23209E073c68Eb9A992f50);

    // JTREASURY_TOKEN
    IERC20MintableLike internal constant TREASURY_TOKEN = IERC20MintableLike(0x8c213ee79581Ff4984583C6a801e5263418C4b86);

    function _getBlock() internal pure override returns (uint256) {
        return 21988625;  // Mar 6, 2025
    }

}

contract MainnetController_Centrifuge_RequestDepositERC7540_Tests is Centrifuge_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        key = makeAddressKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Ethereum.USDC, almProxy, 1_000_000e6);
    }

    function test_requestDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6 + 1);

        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);
    }

    function test_requestDepositERC7540() external {
        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(USDC.allowance(almProxy, address(TREASURY_VAULT)), 0);

        uint256 initialEscrowBal = USDC.balanceOf(ESCROW);

        assertEq(USDC.balanceOf(almProxy), 1_000_000e6);
        assertEq(USDC.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy), 0);

        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(USDC.allowance(almProxy, address(TREASURY_VAULT)), 0);

        assertEq(USDC.balanceOf(almProxy), 0);
        assertEq(USDC.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);
    }

}

contract MainnetController_Centrifuge_ClaimDepositERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_500_000e6, uint256(1_500_000e6) / 1 days);
    }

    function test_claimDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimDepositERC7540(address(TREASURY_VAULT));
    }

    function test_claimDepositERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Lib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.claimDepositERC7540(makeAddr("fake-vault"));
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);

        uint256 totalSupply = TREASURY_TOKEN.totalSupply();

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   1_000_000e6);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Fulfill request at price 2.0
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            1_000_000e6,
            500_000e6
        );

        assertEq(TREASURY_TOKEN.totalSupply(),                totalSupply + 500_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + 500_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);

        // Claim shares
        vm.prank(RELAYER);
        mainnetController.claimDepositERC7540(address(TREASURY_VAULT));

        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 500_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);
    }

    function test_claimDepositERC7540_multipleRequests() external {
        deal(Ethereum.USDC, almProxy, 1_500_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);

        uint256 totalSupply = TREASURY_TOKEN.totalSupply();

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   1_000_000e6);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Request another deposit into JTRSY by supplying more USDC
        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 500_000e6);

        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   1_500_000e6);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);

        // Fulfill both requests at price 2.0
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            1_500_000e6,
            750_000e6
        );

        assertEq(TREASURY_TOKEN.totalSupply(),                totalSupply + 750_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + 750_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 1_500_000e6);

        // Claim shares
        vm.prank(RELAYER);
        mainnetController.claimDepositERC7540(address(TREASURY_VAULT));

        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 750_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableDepositRequest(REQUEST_ID, almProxy), 0);
    }

}

contract MainnetController_Centrifuge_CancelDeposit_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelCentrifugeDepositRequest(address(TREASURY_VAULT));
    }

    function test_cancelCentrifugeDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.cancelCentrifugeDepositRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        vm.prank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),       1_000_000e6);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy), false);

        vm.prank(RELAYER);
        mainnetController.cancelCentrifugeDepositRequest(address(TREASURY_VAULT));

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),       1_000_000e6);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy), true);
    }

}

contract MainnetController_Centrifuge_ClaimCancelDeposit_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimCentrifugeCancelDepositRequest(address(TREASURY_VAULT));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.claimCentrifugeCancelDepositRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        uint256 initialEscrowBal = USDC.balanceOf(ESCROW);

        assertEq(USDC.balanceOf(almProxy), 1_000_000e6);
        assertEq(USDC.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        vm.startPrank(RELAYER);
        mainnetController.requestDepositERC7540(address(TREASURY_VAULT), 1_000_000e6);
        mainnetController.cancelCentrifugeDepositRequest(address(TREASURY_VAULT));
        vm.stopPrank();

        assertEq(USDC.balanceOf(almProxy), 0);
        assertEq(USDC.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),         1_000_000e6);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy),   true);
        assertEq(TREASURY_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillCancelDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            1_000_000e6,
            1_000_000e6
        );

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 1_000_000e6);

        vm.prank(RELAYER);
        mainnetController.claimCentrifugeCancelDepositRequest(address(TREASURY_VAULT));

        assertEq(TREASURY_VAULT.pendingDepositRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelDepositRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelDepositRequest(REQUEST_ID, almProxy), 0);

        assertEq(USDC.balanceOf(almProxy), 1_000_000e6);
        assertEq(USDC.balanceOf(ESCROW),            initialEscrowBal);
    }

}

contract MainnetController_Centrifuge_RequestRedeemERC7540_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        key = makeAddressKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, 1_000_000e6);

        uint256 overBoundaryShares = TREASURY_VAULT.convertToShares(1_000_000e6 + 3);
        uint256 atBoundaryShares   = TREASURY_VAULT.convertToShares(1_000_000e6 + 1);

        assertEq(TREASURY_VAULT.convertToAssets(overBoundaryShares), 1_000_000e6 + 2);
        assertEq(TREASURY_VAULT.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), overBoundaryShares);

        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), atBoundaryShares);
    }

    function test_requestRedeemERC7540() external {
        uint256 shares = TREASURY_VAULT.convertToShares(1_000_000e6);

        assertEq(shares, 948_558.832635e6);

        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), shares);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy), 0);

        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1);  // Rounding

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy), shares);
    }

}

contract MainnetController_Centrifuge_ClaimRedeemERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 2_000_000e6, uint256(2_000_000e6) / 1 days);
    }

    function test_claimRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimRedeemERC7540(address(TREASURY_VAULT));
    }

    function test_claimRedeemERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Lib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.claimRedeemERC7540(makeAddr("fake-vault"));
    }

    function test_claimRedeemERC7540_singleRequest() external {
        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, 1_000_000e6);

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 1_000_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request JTRSY redemption
        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), 1_000_000e6);

        uint256 totalSupply = TREASURY_TOKEN.totalSupply();

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   1_000_000e6);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Fulfill request at price 2.0
        deal(Ethereum.USDC, ESCROW, 2_000_000e6);
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            2_000_000e6,
            1_000_000e6
        );

        assertEq(TREASURY_TOKEN.totalSupply(),                totalSupply - 1_000_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(USDC.balanceOf(ESCROW),            2_000_000e6);
        assertEq(USDC.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 1_000_000e6);

        // Claim assets
        vm.prank(RELAYER);
        mainnetController.claimRedeemERC7540(address(TREASURY_VAULT));

        assertEq(USDC.balanceOf(ESCROW),            0);
        assertEq(USDC.balanceOf(almProxy), 2_000_000e6);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);
    }

    function test_claimRedeemERC7540_multipleRequests() external {
        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, 1_500_000e6);

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 1_500_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request JTRSY redemption
        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), 1_000_000e6);

        uint256 totalSupply = TREASURY_TOKEN.totalSupply();

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 500_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   1_000_000e6);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Request another JTRSY redemption
        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), 500_000e6);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + 1_500_000e6);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   1_500_000e6);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);

        // Fulfill both requests at price 2.0
        deal(Ethereum.USDC, ESCROW, 3_000_000e6);
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            3_000_000e6,
            1_500_000e6
        );

        assertEq(TREASURY_TOKEN.totalSupply(),                totalSupply - 1_500_000e6);
        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(USDC.balanceOf(ESCROW),            3_000_000e6);
        assertEq(USDC.balanceOf(almProxy), 0);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 1_500_000e6);

        // Claim assets
        vm.prank(RELAYER);
        mainnetController.claimRedeemERC7540(address(TREASURY_VAULT));

        assertEq(USDC.balanceOf(ESCROW),            0);
        assertEq(USDC.balanceOf(almProxy), 3_000_000e6);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),   0);
        assertEq(TREASURY_VAULT.claimableRedeemRequest(REQUEST_ID, almProxy), 0);
    }

}

contract MainnetController_Centrifuge_CancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelCentrifugeRedeemRequest(address(TREASURY_VAULT));
    }

    function test_cancelCentrifugeRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.cancelCentrifugeRedeemRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = TREASURY_VAULT.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, shares);

        vm.prank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), shares);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),       shares);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy), false);

        vm.prank(RELAYER);
        mainnetController.cancelCentrifugeRedeemRequest(address(TREASURY_VAULT));

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),       shares);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy), true);
    }

}

contract MainnetController_Centrifuge_ClaimCancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        RESTRICTION_MANAGER.updateMember(address(TREASURY_TOKEN), almProxy, type(uint64).max);

        bytes32 key = makeAddressKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(TREASURY_VAULT)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimCentrifugeCancelRedeemRequest(address(TREASURY_VAULT));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeLib/invalid-action");
        vm.prank(RELAYER);
        mainnetController.claimCentrifugeCancelRedeemRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelRedeemRequest() external {
        uint256 shares = TREASURY_VAULT.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        TREASURY_TOKEN.mint(almProxy, shares);

        uint256 initialEscrowBal = TREASURY_TOKEN.balanceOf(ESCROW);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), shares);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        vm.startPrank(RELAYER);
        mainnetController.requestRedeemERC7540(address(TREASURY_VAULT), shares);
        mainnetController.cancelCentrifugeRedeemRequest(address(TREASURY_VAULT));
        vm.stopPrank();

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), 0);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),         shares);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy),   true);
        assertEq(TREASURY_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        INVESTMENT_MANAGER.fulfillCancelRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            almProxy,
            USDC_ASSET_ID,
            uint128(shares)
        );

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), shares);

        vm.prank(RELAYER);
        mainnetController.claimCentrifugeCancelRedeemRequest(address(TREASURY_VAULT));

        assertEq(TREASURY_VAULT.pendingRedeemRequest(REQUEST_ID, almProxy),         0);
        assertEq(TREASURY_VAULT.pendingCancelRedeemRequest(REQUEST_ID, almProxy),   false);
        assertEq(TREASURY_VAULT.claimableCancelRedeemRequest(REQUEST_ID, almProxy), 0);

        assertEq(TREASURY_TOKEN.balanceOf(almProxy), shares);
        assertEq(TREASURY_TOKEN.balanceOf(ESCROW),            initialEscrowBal);
    }

}
