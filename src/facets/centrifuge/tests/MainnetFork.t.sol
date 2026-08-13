// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../../../lib/spark-address-registry/src/Ethereum.sol";

import { ICentrifugeFacet } from "../ICentrifugeFacet.sol";
import { IERC7540Facet }    from "../../erc7540/IERC7540Facet.sol";

import {
    IAsyncRedeemManagerLike,
    ICentrifugeV3VaultLike,
    IERC20Like,
    IERC20MintableLike,
    IInvestmentManager,
    IRestrictionManager
} from "./Interfaces.sol";

import { MainnetTests } from "../../../../test/fork/Mainnet.t.sol";

abstract contract Mainnet_Centrifuge_Tests is MainnetTests {

    address constant ESCROW                         = 0x0000000005F458Fd6ba9EEb5f365D83b7dA913dD;
    address constant INVESTMENT_MANAGER             = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;
    address constant JTREASURY_RESTRICTION_MANAGER  = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;
    address constant JTREASURY_TOKEN                = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address constant JTREASURY_VAULT_USDC           = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;
    address constant ROOT                           = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;

    bytes16 constant JTREASURY_TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant USDC_ASSET_ID        = 242333941209166991950178742833476896417;
    uint64  constant JTREASURY_POOL_ID    = 4139607887;

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 constant REQUEST_ID = 0;

    IInvestmentManager  investmentManager  = IInvestmentManager(INVESTMENT_MANAGER);
    IRestrictionManager restrictionManager = IRestrictionManager(JTREASURY_RESTRICTION_MANAGER);

    ICentrifugeV3VaultLike jTreasuryVault = ICentrifugeV3VaultLike(JTREASURY_VAULT_USDC);
    IERC20MintableLike     jTreasuryToken = IERC20MintableLike(JTREASURY_TOKEN);

    function _getBlock() internal pure override returns (uint256) {
        return 21988625;  // Mar 6, 2025
    }

}

contract Mainnet_Centrifuge_RequestDepositERC7540_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.erc7540_getRequestDepositRateLimitKey(address(jTreasuryVault), Ethereum.USDC);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);
    }

    function test_requestDepositERC7540_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540() external {
        deal(address(usdc), address(almProxy), 2_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(jTreasuryVault)), 0);

        uint256 initialEscrowBal = usdc.balanceOf(ESCROW);

        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit(address(jTreasuryVault), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.allowance(address(almProxy), address(jTreasuryVault)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract Mainnet_Centrifuge_ClaimDepositERC7540_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.erc7540_getClaimDepositRateLimitKey(address(jTreasuryVault));

        bytes32 requestDepositKey = mainnetController.erc7540_getRequestDepositRateLimitKey(
            address(jTreasuryVault),
            Ethereum.USDC
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestDepositKey, 1_500_000e6, uint256(1_500_000e6) / 1 days);
        rateLimits.setRateLimitData(key,               1_500_000e6, uint256(1_500_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimDepositERC7540_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc7540_claimDeposit(address(jTreasuryVault));
    }

    function test_claimDepositERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc7540_claimDeposit(address(jTreasuryVault));
    }

    function test_claimDepositERC7540_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(allocator);
        mainnetController.erc7540_claimDeposit(address(jTreasuryVault));
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(jTreasuryVault),
            assets : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        vm.prank(ROOT);
        investmentManager.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_000_000e6,
            500_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply + 500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 500_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim shares
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540ClaimDeposit(address(jTreasuryVault), 500_000e6);

        vm.prank(allocator);
        mainnetController.erc7540_claimDeposit(address(jTreasuryVault));

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 500_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

    function test_claimDepositERC7540_multipleRequests() external {
        deal(address(usdc), address(almProxy), 1_500_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(jTreasuryVault),
            assets : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another deposit into JTRSY by supplying more USDC
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(jTreasuryVault),
            assets : 500_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 500_000e6);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_500_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill both requests at price 2.0
        vm.prank(ROOT);
        investmentManager.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_500_000e6,
            750_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply + 750_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 750_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim shares
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540ClaimDeposit({
            token  : address(jTreasuryVault),
            shares : 750_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_claimDeposit(address(jTreasuryVault));

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 750_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract Mainnet_Centrifuge_CancelDeposit_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.centrifuge_getCancelDepositRateLimitKey(address(jTreasuryVault));

        bytes32 requestDepositKey = mainnetController.erc7540_getRequestDepositRateLimitKey(
            address(jTreasuryVault),
            Ethereum.USDC
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestDepositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,               1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_cancelCentrifugeDepositRequest_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_cancelDepositRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeDepositRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_cancelDepositRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeDepositRequest_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.centrifuge_cancelDepositRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(jTreasuryVault),
            assets : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),       1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), false);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeCancelDepositRequest(address(jTreasuryVault));

        vm.prank(allocator);
        mainnetController.centrifuge_cancelDepositRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),       1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract Mainnet_Centrifuge_ClaimCancelDeposit_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.centrifuge_getClaimCancelDepositRateLimitKey(address(jTreasuryVault));

        bytes32 requestDepositKey = mainnetController.erc7540_getRequestDepositRateLimitKey(
            address(jTreasuryVault),
            Ethereum.USDC
        );

        bytes32 cancelDepositKey = mainnetController.centrifuge_getCancelDepositRateLimitKey(
            address(jTreasuryVault)
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestDepositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(cancelDepositKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,               1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimCentrifugeCancelDepositRequest_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_claimCancelDepositRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelDepositRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_claimCancelDepositRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.centrifuge_claimCancelDepositRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(address(usdc), address(almProxy), 2_000_000e6);

        uint256 initialEscrowBal = usdc.balanceOf(ESCROW);

        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(jTreasuryVault),
            assets : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeCancelDepositRequest({ token: address(jTreasuryVault) });

        vm.prank(allocator);
        mainnetController.centrifuge_cancelDepositRequest(address(jTreasuryVault));

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   true);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        investmentManager.fulfillCancelDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_000_000e6,
            1_000_000e6
        );

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeClaimCancelDepositRequest(address(jTreasuryVault), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.centrifuge_claimCancelDepositRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);
    }

}

contract Mainnet_Centrifuge_RequestRedeemERC7540_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.erc7540_getRequestRedeemRateLimitKey(address(jTreasuryVault));

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), 1_000_000e6);

        uint256 overBoundaryShares = jTreasuryVault.convertToShares(1_000_000e6 + 3);
        uint256 atBoundaryShares   = jTreasuryVault.convertToShares(1_000_000e6 + 1);

        assertEq(jTreasuryVault.convertToAssets(overBoundaryShares), 1_000_000e6 + 2);
        assertEq(jTreasuryVault.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), overBoundaryShares);

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), atBoundaryShares);
    }

    function test_requestRedeemERC7540() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        assertEq(shares, 948_558.832635e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem(address(jTreasuryVault), shares);

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1);  // Rounding

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), shares);
    }

}

contract Mainnet_Centrifuge_ClaimRedeemERC7540_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.erc7540_getClaimRedeemRateLimitKey(address(jTreasuryVault));

        bytes32 requestRedeemKey = mainnetController.erc7540_getRequestRedeemRateLimitKey(
            address(jTreasuryVault)
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestRedeemKey, 2_000_000e6, uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              2_000_000e6, uint256(2_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimRedeemERC7540_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.erc7540_claimRedeem(address(jTreasuryVault));
    }

    function test_claimRedeemERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.erc7540_claimRedeem(address(jTreasuryVault));
    }

    function test_claimRedeemERC7540_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(allocator);
        mainnetController.erc7540_claimRedeem(address(jTreasuryVault));
    }

    function test_claimRedeemERC7540_singleRequest() external {
        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request JTRSY redemption
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(jTreasuryVault),
            shares : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        deal(address(usdc), ESCROW, 2_000_000e6);

        vm.prank(ROOT);
        investmentManager.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            2_000_000e6,
            1_000_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply - 1_000_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(usdc.balanceOf(ESCROW),            2_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim assets
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540ClaimRedeem(address(jTreasuryVault), 2_000_000e6);

        vm.prank(allocator);
        mainnetController.erc7540_claimRedeem(address(jTreasuryVault));

        assertEq(usdc.balanceOf(ESCROW),            0);
        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

    function test_claimRedeemERC7540_multipleRequests() external {
        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), 1_500_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 1_500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request JTRSY redemption
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(jTreasuryVault),
            shares : 1_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another JTRSY redemption
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(jTreasuryVault),
            shares : 500_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), 500_000e6);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_500_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_500_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill both requests at price 2.0
        deal(address(usdc), ESCROW, 3_000_000e6);

        vm.prank(ROOT);
        investmentManager.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            3_000_000e6,
            1_500_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply - 1_500_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(usdc.balanceOf(ESCROW),            3_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim assets
        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540ClaimRedeem({
            token  : address(jTreasuryVault),
            assets : 3_000_000e6
        });

        vm.prank(allocator);
        mainnetController.erc7540_claimRedeem(address(jTreasuryVault));

        assertEq(usdc.balanceOf(ESCROW),            0);
        assertEq(usdc.balanceOf(address(almProxy)), 3_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract Mainnet_Centrifuge_CancelRedeemRequest_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.centrifuge_getCancelRedeemRateLimitKey(address(jTreasuryVault));

        bytes32 requestRedeemKey = mainnetController.erc7540_getRequestRedeemRateLimitKey(
            address(jTreasuryVault)
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestRedeemKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_cancelCentrifugeRedeemRequest_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_cancelRedeemRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeRedeemRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_cancelRedeemRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeRedeemRequest_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.centrifuge_cancelRedeemRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem({ token: address(jTreasuryVault), shares: shares });

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),       shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), false);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeCancelRedeemRequest(address(jTreasuryVault));

        vm.prank(allocator);
        mainnetController.centrifuge_cancelRedeemRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),       shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract Mainnet_Centrifuge_ClaimCancelRedeemRequest_Tests is Mainnet_Centrifuge_Tests {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = mainnetController.centrifuge_getClaimCancelRedeemRateLimitKey(address(jTreasuryVault));

        bytes32 requestRedeemKey = mainnetController.erc7540_getRequestRedeemRateLimitKey(
            address(jTreasuryVault)
        );

        bytes32 cancelRedeemKey = mainnetController.centrifuge_getCancelRedeemRateLimitKey(
            address(jTreasuryVault)
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestRedeemKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(cancelRedeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimCentrifugeCancelRedeemRequest_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_claimCancelRedeemRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelRedeemRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_claimCancelRedeemRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.centrifuge_claimCancelRedeemRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelRedeemRequest() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(mainnetController));
        emit IERC7540Facet.ERC7540RequestRedeem({ token: address(jTreasuryVault), shares: shares });

        vm.prank(allocator);
        mainnetController.erc7540_requestRedeem(address(jTreasuryVault), shares);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeCancelRedeemRequest({ token: address(jTreasuryVault) });

        vm.prank(allocator);
        mainnetController.centrifuge_cancelRedeemRequest(address(jTreasuryVault));

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   true);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        investmentManager.fulfillCancelRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            uint128(shares)
        );

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), shares);

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeClaimCancelRedeemRequest(address(jTreasuryVault), shares);

        vm.prank(allocator);
        mainnetController.centrifuge_claimCancelRedeemRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
    }

}

contract Mainnet_Centrifuge_Attack_Tests is Mainnet_Centrifuge_Tests {

    bytes32 depositKey;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        depositKey = mainnetController.erc7540_getRequestDepositRateLimitKey(address(jTreasuryVault), Ethereum.USDC);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 2_000_000e6, uint256(2_000_000e6) / 1 days);
    }

    function test_attack_assetChanged_requestDepositERC7540() external {
        assertEq(rateLimits.getCurrentRateLimit(depositKey), 2_000_000e6);

        // Request succeeds with original underlying (USDC).
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000_000e6);

        // Attack: mock asset() to return a different address.
        address changedAsset = Ethereum.DAI;
        vm.mockCall(
            address(jTreasuryVault),
            abi.encodeWithSignature("asset()"),
            abi.encode(changedAsset)
        );

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        // Cannot request another deposit with the changed asset.
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.erc7540_requestDeposit(address(jTreasuryVault), 1_000_000e6);
    }

}

contract Mainnet_Centrifuge_TransferShares_Tests is MainnetTests {

    event InitiateTransferShares(
        uint16          centrifugeId,
        uint64  indexed poolId,
        bytes16 indexed scId,
        address indexed sender,
        bytes32         destinationAddress,
        uint128         amount
    );

    address constant CENTRIFUGE_VAULT = 0x1121F4e21eD8B9BC1BB9A2952cDD8639aC897784; // DEJAAA_VAULT_USDC

    uint16  constant DESTINATION_CENTRIFUGE_ID = 5; // Avalanche Centrifuge ID

    ICentrifugeV3VaultLike centrifugeVault = ICentrifugeV3VaultLike(CENTRIFUGE_VAULT);

    IAsyncRedeemManagerLike manager;

    address root;
    address spoke;
    address vaultToken;

    uint64  poolId;
    bytes16 scId;

    bytes32 internal target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

    function setUp() public override virtual {
        super.setUp();

        root       = centrifugeVault.root();
        vaultToken = centrifugeVault.share();
        manager    = IAsyncRedeemManagerLike(centrifugeVault.manager());
        spoke      = manager.spoke();

        poolId = centrifugeVault.poolId();
        scId   = centrifugeVault.scId();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22968402;  // Jul 21, 2025
    }

    function test_transferSharesCentrifuge_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        deal(allocator, 0.1 ether);

        vm.expectRevert("CentrifugeFacet/id-not-configured");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        rateLimits.setRateLimitData(
            mainnetController.centrifuge_getTransferRateLimitKey(CENTRIFUGE_VAULT, DESTINATION_CENTRIFUGE_ID, address(spoke)),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        // Setup token balances
        deal(vaultToken, address(almProxy), 20_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for Centrifuge

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge() external {
        vm.startPrank(SPARK_PROXY);

        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        rateLimits.setRateLimitData(
            mainnetController.centrifuge_getTransferRateLimitKey(CENTRIFUGE_VAULT, DESTINATION_CENTRIFUGE_ID, address(spoke)),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), address(almProxy), 20_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for Centrifuge

        // Issue shares at price 1.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            10_000_000e6,
            1e18
        );

        uint256 proxyBalanceBefore     = IERC20Like(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyBefore = IERC20Like(vaultToken).totalSupply();

        vm.expectEmit(address(spoke));
        emit InitiateTransferShares({
            centrifugeId       : DESTINATION_CENTRIFUGE_ID,
            poolId             : poolId,
            scId               : scId,
            sender             : address(almProxy),
            destinationAddress : target,
            amount             : 10_000_000e6
        });

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeTransferShares(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        uint256 proxyBalanceAfter     = IERC20Like(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyAfter = IERC20Like(vaultToken).totalSupply();

        assertEq(proxyBalanceAfter,     proxyBalanceBefore     - 10_000_000e6);
        assertEq(shareTotalSupplyAfter, shareTotalSupplyBefore - 10_000_000e6);
    }

}
