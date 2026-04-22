// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { IBuffer } from "../IBuffer.sol";
import { Facet }   from "../Facet.sol";

import { IWEETHFacet }  from "./IWEETHFacet.sol";

import { WEETHBuffer } from "./WEETHBuffer.sol";

interface IEETHLike {

    function liquidityPool() external view returns (address);

}

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address owner) external view returns (uint256);

}

interface ILiquidityPoolLike {

    function amountForShare(uint256 shareAmount) external view returns (uint256);

    function sharesForAmount(uint256 amount) external view returns (uint256);

    function deposit() external payable returns (uint256 shareAmount);

    function requestWithdraw(address receiver, uint256 amount) external returns (uint256 requestId);

    function withdrawRequestNFT() external view returns (address);

}

interface IWEETHLike {

    function eETH() external view returns (address);

    function unwrap(uint256 amount) external returns (uint256);

    function wrap(uint256 amount) external returns (uint256);

}

interface IWETHLike {

    function deposit() external payable;

    function withdraw(uint256 amount) external;

}

interface IWithdrawRequestNFTLike {

    function claimWithdraw(uint256 requestId) external;

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);

}

contract WEETHFacet is IWEETHFacet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.WEETHFacet.v1
    struct FacetStorage {
        address buffer;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.WEETHFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x087bb3711461a2b608e03039b70c79e87f693cffc9be142fc6eadf16219e5900;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IWEETHFacet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_WEETH_DEPOSIT");

    /// @inheritdoc IWEETHFacet
    bytes32 public constant override LIMIT_REQUEST_WITHDRAW =
        keccak256("LIMIT_WEETH_REQUEST_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IWEETHFacet
    address public immutable override weeth;

    /// @inheritdoc IWEETHFacet
    address public immutable override weth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weeth_, address weth_) {
        require(weeth_ != address(0), "WEETHFacet/zero-weeth");
        require(weth_  != address(0), "WEETHFacet/zero-weth");

        weeth = weeth_;
        weth  = weth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IWEETHFacet
    function deposit(uint256 amount, uint256 minSharesOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_DEPOSIT, amount);

        address proxy = $.proxy;

        // Unwrap WETH to ETH.
        IALMProxy(proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        // Deposit ETH to eETH.
        address eeth          = IWEETHLike(weeth).eETH();
        address liquidityPool = IEETHLike(eeth).liquidityPool();

        uint256 eethShares = abi.decode(
            IALMProxy(proxy).doCallWithValue(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike.deposit, ()),
                amount
            ),
            (uint256)
        );

        uint256 eethAmount = ILiquidityPoolLike(liquidityPool).amountForShare(eethShares);

        // Deposit eETH to weETH.
        ApproveLib.approve(eeth, proxy, weeth, eethAmount);

        shares = abi.decode(
            IALMProxy(proxy).doCall(weeth, abi.encodeCall(IWEETHLike.wrap, (eethAmount))),
            (uint256)
        );

        require(shares >= minSharesOut, "WEETHFacet/slippage-too-high");

        emit WEETHDeposit(amount, eethAmount, shares);
    }

    /// @inheritdoc IWEETHFacet
    function requestWithdraw(uint256 weethShares, uint256 minEETHShares)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 requestId)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy         = $.proxy;
        address eeth          = IWEETHLike(weeth).eETH();
        address liquidityPool = IEETHLike(eeth).liquidityPool();

        // Withdraw from weETH (returns eETH).
        uint256 eethAmount = abi.decode(
            IALMProxy(proxy).doCall(
                weeth,
                abi.encodeCall(IWEETHLike.unwrap, (weethShares))
            ),
            (uint256)
        );

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_REQUEST_WITHDRAW, eethAmount);

        // Protect against cumulative rate slippage across both conversions.
        require(
            ILiquidityPoolLike(liquidityPool).sharesForAmount(eethAmount) >= minEETHShares,
            "WEETHFacet/slippage-too-high"
        );

        // Request withdrawal of ETH from eETH.
        ApproveLib.approve(eeth, proxy, liquidityPool, eethAmount);

        address buffer = _getOrCreateBuffer();

        requestId = abi.decode(
            IALMProxy(proxy).doCall(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike.requestWithdraw, (buffer, eethAmount))
            ),
            (uint256)
        );

        emit WEETHRequestWithdraw(buffer, requestId, eethAmount, weethShares);
    }

    /// @inheritdoc IWEETHFacet
    function claimWithdrawal(uint256 requestId)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 wethReceived)
    {
        address eeth               = IWEETHLike(weeth).eETH();
        address liquidityPool      = IEETHLike(eeth).liquidityPool();
        address withdrawRequestNFT = ILiquidityPoolLike(liquidityPool).withdrawRequestNFT();

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isValid(requestId),
            "WEETHFacet/invalid-request-id"
        );

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isFinalized(requestId),
            "WEETHFacet/request-not-finalized"
        );

        address proxy = _getSharedControllerStorage().proxy;
        address buffer = _getOrCreateBuffer();

        // Instruct the proxy to instruct the buffer to claim the withdrawal of ETH from eETH.
        IALMProxy(proxy).doCall(
            buffer,
            abi.encodeCall(
                IBuffer.doCall,
                (
                    withdrawRequestNFT,
                    abi.encodeCall(IWithdrawRequestNFTLike.claimWithdraw, (requestId))
                )
            )
        );

        // Instruct the proxy to instruct the buffer to deposit the ETH into WETH.
        IALMProxy(proxy).doCall(
            buffer,
            abi.encodeCall(
                IBuffer.doCallWithValue,
                (
                    weth,
                    abi.encodeCall(IWETHLike.deposit, ()),
                    buffer.balance
                )
            )
        );

        uint256 startingBalance = IERC20Like(weth).balanceOf(proxy);

        // Instruct the proxy to instruct the buffer to transfer the ETH into WETH.
        IALMProxy(proxy).doCall(
            buffer,
            abi.encodeCall(
                IBuffer.doCall,
                (
                    weth,
                    abi.encodeCall(IERC20Like.transfer, (proxy, IERC20Like(weth).balanceOf(buffer)))
                )
            )
        );

        wethReceived = IERC20Like(weth).balanceOf(proxy) - startingBalance;

        emit WEETHClaimWithdrawal(buffer, requestId, wethReceived);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IWEETHFacet
    function buffer() external view override returns (address) {
        return _getFacetStorage().buffer;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function _getOrCreateBuffer() internal returns (address buffer) {
        FacetStorage storage $ = _getFacetStorage();

        buffer = $.buffer;

        if (buffer != address(0)) return buffer;

        buffer = address(new WEETHBuffer{salt: bytes32(0)}(_getSharedControllerStorage().proxy));

        emit WEETHBufferCreated($.buffer = buffer);
    }

}
