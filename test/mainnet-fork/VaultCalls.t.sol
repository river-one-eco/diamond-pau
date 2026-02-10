// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AllocatorDeploy } from "../../lib/dss-allocator/deploy/AllocatorDeploy.sol";

import { AllocatorInit, AllocatorIlkConfig } from "../../lib/dss-allocator/deploy/AllocatorInit.sol";

import {
    AllocatorIlkInstance,
    AllocatorSharedInstance
} from "../../lib/dss-allocator/deploy/AllocatorInstances.sol";

import { DssInstance, MCD } from "../../lib/dss-test/src/MCD.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { RateLimits } from "../../src/RateLimits.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IBufferLike {

    function approve(address, address, uint256) external;

}

interface IChainlogLike {

    function getAddress(bytes32) external view returns (address);

}

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IVaultLike {

    function buffer() external view returns (address);

    function rely(address) external;

}

abstract contract Vault_TestBase is ForkTestBase {

    address internal constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 internal constant ILK_A = "ILK-A";

    uint256 internal constant INK           = 1e12 * 1e18;  // Ink initialization amount
    uint256 internal constant RAD           = 10 ** 45;
    uint256 internal constant EIGHT_PCT_APY = 1.000000002440418608258400030e27;  // 8% APY (current DSR + 1%)

    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    DssInstance internal dss;

    address internal buffer;
    address internal vault;

    address internal usdsJoin;

    uint256 internal usdsSupply;

    uint256 internal vatDAIUSDSJoin;

    function setUp() public virtual override {
        super.setUp();

        usdsSupply = IERC20Like(Ethereum.USDS).totalSupply();

        dss = MCD.loadFromChainlog(LOG);

        usdsJoin = IChainlogLike(LOG).getAddress("USDS_JOIN");

        vatDAIUSDSJoin = dss.vat.dai(usdsJoin);

        AllocatorSharedInstance memory sharedInst
            = AllocatorDeploy.deployShared(address(this), Ethereum.PAUSE_PROXY); // TODO: Fix address(this).

        AllocatorIlkInstance memory ilkInst = AllocatorDeploy.deployIlk({
            deployer : address(this), // TODO: Fix address(this).
            owner    : Ethereum.PAUSE_PROXY,
            roles    : sharedInst.roles,
            ilk      : ILK_A,
            usdsJoin : usdsJoin
        });

        AllocatorIlkConfig memory ilkConfig = AllocatorIlkConfig({
            ilk            : ILK_A,
            duty           : EIGHT_PCT_APY,
            maxLine        : 100_000_000 * RAD,
            gap            : 10_000_000 * RAD,
            ttl            : 6 hours,
            allocatorProxy : Ethereum.SPARK_PROXY,
            ilkRegistry    : IChainlogLike(LOG).getAddress("ILK_REGISTRY")
        });

        vm.startPrank(Ethereum.PAUSE_PROXY);
        AllocatorInit.initShared(dss, sharedInst);
        AllocatorInit.initIlk(dss, sharedInst, ilkInst, ilkConfig);
        vm.stopPrank();

        buffer = ilkInst.buffer;
        vault  = ilkInst.vault;

        vm.startPrank(Ethereum.SPARK_PROXY);

        IVaultLike(vault).rely(almProxy);
        IBufferLike(buffer).approve(Ethereum.USDS, almProxy, type(uint256).max);

        mainnetController.setUSDSVault(vault);

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_USDS_MINT(),
            uint256(5_000_000e18),
            uint256(1_000_000e18) / 4 hours
        );

        vm.stopPrank();
    }

}

contract MainnetController_Vault_MintUSDS_Tests is Vault_TestBase {

    function test_mintUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.mintUSDS(1e18);
    }

    function test_mintUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.mintUSDS(1e18);
    }

    function test_mintUSDS_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.mintUSDS(1e18);
    }

    function test_mintUSDS_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(RELAYER);
        mainnetController.mintUSDS(5_000_000e18 + 1);

        vm.prank(RELAYER);
        mainnetController.mintUSDS(5_000_000e18);
    }

    function test_mintUSDS() external {
        ( uint256 ink, uint256 art ) = dss.vat.urns(ILK_A, vault);
        ( uint256 Art, , , , )       = dss.vat.ilks(ILK_A);

        assertEq(dss.vat.dai(usdsJoin), vatDAIUSDSJoin);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(USDS.balanceOf(almProxy), 0);
        assertEq(USDS.totalSupply(),       usdsSupply);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.mintUSDS(1e18);

        _assertReentrancyGuardWrittenToTwice();

        ( ink, art )   = dss.vat.urns(ILK_A, vault);
        ( Art, , , , ) = dss.vat.ilks(ILK_A);

        assertEq(dss.vat.dai(usdsJoin), vatDAIUSDSJoin + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(USDS.balanceOf(almProxy), 1e18);
        assertEq(USDS.totalSupply(),       usdsSupply + 1e18);
    }

    function test_mintUSDS_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDS_MINT();

        vm.startPrank(RELAYER);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            0);

        mainnetController.mintUSDS(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            1_000_000e18);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.9999999999999984e18);
        assertEq(USDS.balanceOf(almProxy),            1_000_000e18);

        mainnetController.mintUSDS(4_249_999.9999999999999984e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
        assertEq(USDS.balanceOf(almProxy),            5_249_999.9999999999999984e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.mintUSDS(1);

        vm.stopPrank();
    }

}

contract MainnetController_Vault_BurnUSDS_Tests is Vault_TestBase {

    function test_burnUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.burnUSDS(1e18);
    }

    function test_burnUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.burnUSDS(1e18);
    }

    function test_burnUSDS_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(RELAYER);
        mainnetController.burnUSDS(1e18);
    }

    function test_burnUSDS() external {
        // Setup
        vm.prank(RELAYER);
        mainnetController.mintUSDS(1e18);

        ( uint256 ink, uint256 art ) = dss.vat.urns(ILK_A, vault);
        ( uint256 Art, , , , )       = dss.vat.ilks(ILK_A);

        assertEq(dss.vat.dai(usdsJoin), vatDAIUSDSJoin + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(USDS.balanceOf(almProxy), 1e18);
        assertEq(USDS.totalSupply(),       usdsSupply + 1e18);

        vm.record();

        vm.prank(RELAYER);
        mainnetController.burnUSDS(1e18);

        _assertReentrancyGuardWrittenToTwice();

        ( ink, art )   = dss.vat.urns(ILK_A, vault);
        ( Art, , , , ) = dss.vat.ilks(ILK_A);

        assertEq(dss.vat.dai(usdsJoin), vatDAIUSDSJoin);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(USDS.balanceOf(almProxy), 0);
        assertEq(USDS.totalSupply(),       usdsSupply);
    }

    function test_burnUSDS_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDS_MINT();

        vm.startPrank(RELAYER);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            0);

        mainnetController.mintUSDS(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            1_000_000e18);

        mainnetController.burnUSDS(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_500_000e18);
        assertEq(USDS.balanceOf(almProxy),            500_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            500_000e18);

        mainnetController.burnUSDS(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);
        assertEq(USDS.balanceOf(almProxy),            0);

        vm.stopPrank();
    }

}
