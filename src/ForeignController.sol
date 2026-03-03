// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { CentrifugeLib }    from "./libraries/CentrifugeLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { ERC7540Lib }       from "./libraries/ERC7540Lib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { PendleLib }        from "./libraries/PendleLib.sol";
import { MerklLib }         from "./libraries/MerklLib.sol";
import { PSM3Lib }          from "./libraries/PSM3Lib.sol";
import { SparkVaultLib }    from "./libraries/SparkVaultLib.sol";
import { TransferAssetLib } from "./libraries/TransferAssetLib.sol";
import { UniswapV3Lib }     from "./libraries/UniswapV3Lib.sol";

contract ForeignController is ReentrancyGuard, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    event PendleRouterSet(address indexed pendleRouter);

    event MerklDistributorSet(address indexed merklDistributor);

    event UniswapV3SwapRouterSet(address indexed swapRouter);

    event UniswapV3PositionManagerSet(address indexed manager);

    event PSM3Set(address indexed psm);

    event CCTPTokenMessengerSet(address indexed messenger);

    event CCTPUSDCSet(address indexed usdc);

    /**********************************************************************************************/
    /*** Roles                                                                                  ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Rate Limits Keys                                                                       ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_4626_DEPOSIT        = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_4626_WITHDRAW       = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_7540_DEPOSIT        = ERC7540Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_7540_REDEEM         = ERC7540Lib.LIMIT_REDEEM;
    bytes32 public constant LIMIT_AAVE_DEPOSIT        = AaveLib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_AAVE_WITHDRAW       = AaveLib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_ASSET_TRANSFER      = TransferAssetLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_CENTRIFUGE_TRANSFER = CentrifugeLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER  = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_PSM_DEPOSIT         = PSM3Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_PSM_WITHDRAW        = PSM3Lib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_SPARK_VAULT_TAKE    = SparkVaultLib.LIMIT_TAKE;
    bytes32 public constant LIMIT_USDC_TO_CCTP        = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public constant LIMIT_USDC_TO_DOMAIN      = CCTPLib.LIMIT_TO_DOMAIN;
    bytes32 public constant LIMIT_PENDLE_PT_REDEEM    = PendleLib.LIMIT_REDEEM;
    bytes32 public constant LIMIT_UNISWAP_V3_DEPOSIT  = UniswapV3Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_UNISWAP_V3_SWAP     = UniswapV3Lib.LIMIT_SWAP;
    bytes32 public constant LIMIT_UNISWAP_V3_WITHDRAW = UniswapV3Lib.LIMIT_WITHDRAW;

    /**********************************************************************************************/
    /*** Controller State Variables                                                             ***/
    /**********************************************************************************************/

    address public immutable proxy;
    address public immutable rateLimits;

    /**********************************************************************************************/
    /*** Integration-Specific State Variables                                                   ***/
    /**********************************************************************************************/

    address public cctpTokenMessenger;
    address public cctpUSDC;
    address public merklDistributor;
    address public pendleRouter;
    address public psm3;
    address public uniswapV3PositionManager;
    address public uniswapV3Router;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;
    mapping(uint16 destinationCentrifugeId => bytes32 recipient)        public centrifugeRecipients;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

    // Uniswap V3 pool params
    mapping(address pool => UniswapV3Lib.PoolParams params) public uniswapV3PoolParams;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin_, address proxy_, address rateLimits_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = proxy_;
        rateLimits = rateLimits_;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "FC/pool-zero-address");
        emit MaxSlippageSet(pool, maxSlippages[pool] = maxSlippage);
    }

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CCTPLib.setMintRecipient(mintRecipients, recipient, destinationDomain);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LayerZeroLib.setRecipient(layerZeroRecipients, destinationEndpointId, recipient);
    }

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ERC4626Lib.setMaxExchangeRate(maxExchangeRates, token, shares, maxExpectedAssets);
    }

    function setPendleRouter(address router)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit PendleRouterSet(pendleRouter = router);
    }

    function setMerklDistributor(address distributor)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit MerklDistributorSet(merklDistributor = distributor);
    }

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CentrifugeLib.setCentrifugeRecipient(centrifugeRecipients, centrifugeId, recipient);
    }

    function setUniswapV3PositionManager(address manager)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3PositionManagerSet(uniswapV3PositionManager = manager);
    }

    function setUniswapV3SwapRouter(address router)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3SwapRouterSet(uniswapV3Router = router);
    }

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setPoolMaxTickDelta(pool, maxTickDelta, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityLowerTickBound(pool, lowerTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityUpperTickBound(pool, upperTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3TWAPSecondsAgo(address pool, uint32 twapSecondsAgo)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setTWAPSecondsAgo(pool, twapSecondsAgo, uniswapV3PoolParams);
    }

    function setPSM3(address psm) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emit PSM3Set(psm3 = psm);
    }

    function setCCTPTokenMessenger(address messenger)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPTokenMessengerSet(cctpTokenMessenger = messenger);
    }

    function setCCTPUSDC(address usdc) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emit CCTPUSDCSet(cctpUSDC = usdc);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        TransferAssetLib.transfer(proxy, rateLimits, asset, destination, amount);
    }

    /**********************************************************************************************/
    /*** Relayer UniswapV3 functions                                                            ***/
    /**********************************************************************************************/

    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  maxTickDelta
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return UniswapV3Lib.swap({
            proxy        : proxy,
            rateLimits   : rateLimits,
            pool         : pool,
            router       : uniswapV3Router,
            tokenIn      : tokenIn,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            tickDelta    : maxTickDelta,
            poolParams   : uniswapV3PoolParams
        });
    }

    function addLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        UniswapV3Lib.Ticks        calldata ticks,
        UniswapV3Lib.TokenAmounts calldata target,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 tokenId_, uint128 liquidity_, UniswapV3Lib.TokenAmounts memory amounts_)
    {
        ( tokenId_, liquidity_, amounts_ ) = UniswapV3Lib.addLiquidity({
            proxy           : proxy,
            rateLimits      : rateLimits,
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            ticks           : ticks,
            target          : target,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages,
            poolParams      : uniswapV3PoolParams
        });
    }

    function removeLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        uint128                            liquidity,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (UniswapV3Lib.TokenAmounts memory amounts_)
    {
        return UniswapV3Lib.removeLiquidity({
            proxy           : proxy,
            rateLimits      : rateLimits,
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            liquidity       : liquidity,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages
        });
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return PSM3Lib.deposit(proxy, rateLimits, psm3, asset, amount);
    }

    function withdrawPSM(address asset, uint256 maxAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 assetsWithdrawn)
    {
        return PSM3Lib.withdraw(proxy, rateLimits, psm3, asset, maxAmount);
    }

    /**********************************************************************************************/
    /*** Relayer bridging functions                                                             ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CCTPLib.transfer({
            proxy             : proxy,
            rateLimits        : rateLimits,
            cctp              : cctpTokenMessenger,
            usdc              : cctpUSDC,
            destinationDomain : destinationDomain,
            usdcAmount        : usdcAmount,
            mintRecipients    : mintRecipients
        });
    }

    /**********************************************************************************************/
    /*** LayerZero functions                                                                    ***/
    /**********************************************************************************************/

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    function transferTokenLayerZero(
        address oftAddress,
        uint256 amount,
        uint32  destinationEndpointId
    )
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        LayerZeroLib.transfer({
            proxy                 : proxy,
            rateLimits            : rateLimits,
            oftAddress            : oftAddress,
            amount                : amount,
            destinationEndpointId : destinationEndpointId,
            layerZeroRecipients   : layerZeroRecipients
        });
    }

    /**********************************************************************************************/
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return ERC4626Lib.deposit(proxy, rateLimits, token, amount, minSharesOut, maxExchangeRates);
    }

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return ERC4626Lib.withdraw(proxy, rateLimits, token, amount, maxSharesIn);
    }

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 assets)
    {
        return ERC4626Lib.redeem(proxy, rateLimits, token, shares, minAssetsOut);
    }

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256) {
        return ERC4626Lib.EXCHANGE_RATE_PRECISION;
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external nonReentrant onlyRole(RELAYER) {
        AaveLib.deposit(proxy, rateLimits, aToken, amount, maxSlippages);
    }

    function withdrawAave(address aToken, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountWithdrawn)
    {
        return AaveLib.withdraw(proxy, rateLimits, aToken, amount);
    }

    /**********************************************************************************************/
    /*** Relayer Merkl functions                                                                ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address operator) external nonReentrant onlyRole(RELAYER) {
        MerklLib.toggleOperator({
            proxy       : proxy,
            distributor : merklDistributor,
            operator    : operator
        });
    }

    /**********************************************************************************************/
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        SparkVaultLib.take(proxy, rateLimits, sparkVault, assetAmount);
    }

    /**********************************************************************************************/
    /*** Relayer Pendle functions                                                               ***/
    /**********************************************************************************************/

    function redeemPendlePT(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        PendleLib.redeem({
            proxy        : proxy,
            rateLimits   : rateLimits,
            market       : pendleMarket,
            router       : pendleRouter,
            pyAmountIn   : pyAmountIn,
            minAmountOut : minAmountOut
        });
    }

    /**********************************************************************************************/
    /*** Relayer ERC7540 functions                                                              ***/
    /**********************************************************************************************/

    function requestDepositERC7540(address token, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        ERC7540Lib.requestDeposit(proxy, rateLimits, token, amount);
    }

    function claimDepositERC7540(address token) external nonReentrant onlyRole(RELAYER) {
        ERC7540Lib.claimDeposit(proxy, rateLimits, token);
    }

    function requestRedeemERC7540(address token, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        ERC7540Lib.requestRedeem(proxy, rateLimits, token, shares);
    }

    function claimRedeemERC7540(address token) external nonReentrant onlyRole(RELAYER) {
        ERC7540Lib.claimRedeem(proxy, rateLimits, token);
    }

    /**********************************************************************************************/
    /*** Relayer Centrifuge functions                                                           ***/
    /**********************************************************************************************/

    // NOTE: These cancellation methods are compatible with ERC-7887

    function cancelCentrifugeDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelDepositRequest(proxy, rateLimits, token);
    }

    function claimCentrifugeCancelDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelDepositRequest(proxy, rateLimits, token);
    }

    function cancelCentrifugeRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelRedeemRequest(proxy, rateLimits, token);
    }

    function claimCentrifugeCancelRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelRedeemRequest(proxy, rateLimits, token);
    }

    function transferSharesCentrifuge(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.transferShares({
            proxy        : proxy,
            rateLimits   : rateLimits,
            token        : token,
            centrifugeId : centrifugeId,
            amount       : amount,
            recipients   : centrifugeRecipients
        });
    }

}
