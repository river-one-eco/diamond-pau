// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { CentrifugeLib }    from "./libraries/CentrifugeLib.sol";
import { CurveLib }         from "./libraries/CurveLib.sol";
import { DAIUSDSLib }       from "./libraries/DAIUSDSLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { ERC7540Lib }       from "./libraries/ERC7540Lib.sol";
import { FarmLib }          from "./libraries/FarmLib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { MapleLib }         from "./libraries/MapleLib.sol";
import { MerklLib }         from "./libraries/MerklLib.sol";
import { OTCLib }           from "./libraries/OTCLib.sol";
import { PendleLib }        from "./libraries/PendleLib.sol";
import { PSMLib }           from "./libraries/PSMLib.sol";
import { SparkVaultLib }    from "./libraries/SparkVaultLib.sol";
import { SuperstateLib }    from "./libraries/SuperstateLib.sol";
import { TransferAssetLib } from "./libraries/TransferAssetLib.sol";
import { UniswapV3Lib }     from "./libraries/UniswapV3Lib.sol";
import { UniswapV4Lib }     from "./libraries/UniswapV4Lib.sol";
import { USDELib }          from "./libraries/USDELib.sol";
import { USDSLib }          from "./libraries/USDSLib.sol";
import { WEETHLib }         from "./libraries/WEETHLib.sol";
import { WrapProxyETHLib }  from "./libraries/WrapProxyETHLib.sol";
import { WSTETHLib }        from "./libraries/WSTETHLib.sol";

contract MainnetController is ReentrancyGuard, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    event PendleRouterSet(address indexed pendleRouter);

    event MerklDistributorSet(address indexed merklDistributor);

    event UniswapV3SwapRouterSet(address indexed swapRouter);

    event UniswapV3PositionManagerSet(address indexed manager);

    event EthenaMinterSet(address indexed minter);

    event CCTPTokenMessengerSet(address indexed messenger);

    event CCTPUSDCSet(address indexed usdc);

    event USDSVaultSet(address indexed vault);

    /**********************************************************************************************/
    /*** Roles                                                                                  ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Rate Limits Keys                                                                       ***/
    /**********************************************************************************************/

    bytes32 public LIMIT_4626_DEPOSIT            = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_4626_WITHDRAW           = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_7540_DEPOSIT            = ERC7540Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_7540_REDEEM             = ERC7540Lib.LIMIT_REDEEM;
    bytes32 public LIMIT_AAVE_DEPOSIT            = AaveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_AAVE_WITHDRAW           = AaveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_ASSET_TRANSFER          = TransferAssetLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_CENTRIFUGE_TRANSFER     = CentrifugeLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_CURVE_DEPOSIT           = CurveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_CURVE_SWAP              = CurveLib.LIMIT_SWAP;
    bytes32 public LIMIT_CURVE_WITHDRAW          = CurveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_FARM_DEPOSIT            = FarmLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_FARM_WITHDRAW           = FarmLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_LAYERZERO_TRANSFER      = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_MAPLE_REDEEM            = MapleLib.LIMIT_REDEEM;
    bytes32 public LIMIT_OTC_SWAP                = OTCLib.LIMIT_SWAP;
    bytes32 public LIMIT_SPARK_VAULT_TAKE        = SparkVaultLib.LIMIT_TAKE;
    bytes32 public LIMIT_SUPERSTATE_SUBSCRIBE    = SuperstateLib.LIMIT_SUBSCRIBE;
    bytes32 public LIMIT_SUSDE_COOLDOWN          = USDELib.LIMIT_SUSDE_COOLDOWN;
    bytes32 public LIMIT_UNISWAP_V3_DEPOSIT      = UniswapV3Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V3_SWAP         = UniswapV3Lib.LIMIT_SWAP;
    bytes32 public LIMIT_UNISWAP_V3_WITHDRAW     = UniswapV3Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_DEPOSIT      = UniswapV4Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V4_WITHDRAW     = UniswapV4Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_SWAP         = UniswapV4Lib.LIMIT_SWAP;
    bytes32 public LIMIT_USDC_TO_CCTP            = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public LIMIT_USDC_TO_DOMAIN          = CCTPLib.LIMIT_TO_DOMAIN;
    bytes32 public LIMIT_USDE_BURN               = USDELib.LIMIT_USDE_BURN;
    bytes32 public LIMIT_USDE_MINT               = USDELib.LIMIT_USDE_MINT;
    bytes32 public LIMIT_USDS_MINT               = USDSLib.LIMIT_MINT;
    bytes32 public LIMIT_USDS_TO_USDC            = PSMLib.LIMIT_USDS_TO_USDC;
    bytes32 public LIMIT_WEETH_DEPOSIT           = WEETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WEETH_REQUEST_WITHDRAW  = WEETHLib.LIMIT_REQUEST_WITHDRAW;
    bytes32 public LIMIT_WSTETH_DEPOSIT          = WSTETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WSTETH_REQUEST_WITHDRAW = WSTETHLib.LIMIT_REQUEST_WITHDRAW;
    bytes32 public LIMIT_PENDLE_PT_REDEEM        = PendleLib.LIMIT_REDEEM;

    address public buffer;

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
    address public ethenaMinter;
    address public merklDistributor;
    address public pendleRouter;
    address public uniswapV3PositionManager;
    address public uniswapV3Router;
    address public usdsVault;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain       => bytes32 mintRecipient)       public mintRecipients;  // CCTP mint recipients
    mapping(uint32 destinationEndpointId   => bytes32 layerZeroRecipient)  public layerZeroRecipients;
    mapping(uint16 destinationCentrifugeId => bytes32 centrifugeRecipient) public centrifugeRecipients;

    // OTC swap (also uses maxSlippages)
    mapping(address exchange => OTCLib.OTC otcData) public otcs;

    mapping(address exchange => mapping(address asset => bool)) public otcWhitelistedAssets;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

    // Uniswap V3 pool params
    mapping(address pool => UniswapV3Lib.PoolParams params) public uniswapV3PoolParams;

    // Uniswap V4 tick ranges
    mapping(bytes32 poolId => UniswapV4Lib.TickLimits tickLimits) public uniswapV4TickLimits;

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

    function setMerklDistributor(address distributor)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit MerklDistributorSet(merklDistributor = distributor);
    }

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "MC/pool-zero-address");

        emit MaxSlippageSet(pool, maxSlippages[pool] = maxSlippage);
    }

    function setPendleRouter(address router)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit PendleRouterSet(pendleRouter = router);
    }

    function setOTCBuffer(address exchange, address otcBuffer)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setBuffer(exchange, otcBuffer, otcs, maxSlippages);
    }

    function setOTCRechargeRate(address exchange, uint256 rechargeRate18)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setRechargeRate(exchange, rechargeRate18, otcs);
    }

    function setOTCWhitelistedAsset(address exchange, address asset, bool isWhitelisted)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setWhitelistedAsset(exchange, asset, isWhitelisted, otcWhitelistedAssets, otcs);
    }

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ERC4626Lib.setMaxExchangeRate(maxExchangeRates, token, shares, maxExpectedAssets);
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

    function setUniswapV4TickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV4Lib.setTickLimits(
            poolId,
            tickLowerMin,
            tickUpperMax,
            maxTickSpacing,
            uniswapV4TickLimits
        );
    }

    function setUSDSVault(address vault) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emit USDSVaultSet(usdsVault = vault);
    }

    function setEthenaMinter(address minter) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        emit EthenaMinterSet(ethenaMinter = minter);
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

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CentrifugeLib.setCentrifugeRecipient(centrifugeRecipients, centrifugeId, recipient);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer vault functions                                                                ***/
    /**********************************************************************************************/

    function mintUSDS(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        USDSLib.mint(proxy, rateLimits, usdsVault, usdsAmount);
    }

    function burnUSDS(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        USDSLib.burn(proxy, rateLimits, usdsVault, usdsAmount);
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
    /*** wstETH Integration                                                                     ***/
    /**********************************************************************************************/

    function depositToWSTETH(uint256 amount) external nonReentrant onlyRole(RELAYER) {
        WSTETHLib.deposit(proxy, rateLimits, amount);
    }

    function requestWithdrawFromWSTETH(uint256 amountToRedeem)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256[] memory requestIds)
    {
        return WSTETHLib.requestWithdraw(proxy, rateLimits, amountToRedeem);
    }

    function claimWithdrawalFromWSTETH(uint256 requestId) external nonReentrant onlyRole(RELAYER) {
        WSTETHLib.claimWithdrawal(proxy, requestId);
    }

    /**********************************************************************************************/
    /*** weETH Integration                                                                      ***/
    /**********************************************************************************************/

    function depositToWEETH(uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return WEETHLib.deposit(proxy, rateLimits, amount, minSharesOut);
    }

    function requestWithdrawFromWEETH(
        address weethModule,
        uint256 weethShares,
        uint256 minEETHShares
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 requestId)
    {
        return WEETHLib.requestWithdraw(proxy, rateLimits, weethModule, weethShares, minEETHShares);
    }

    function claimWithdrawalFromWEETH(address weethModule, uint256 requestId)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 ethReceived)
    {
        return WEETHLib.claimWithdrawal(proxy, rateLimits, weethModule, requestId);
    }

    /**********************************************************************************************/
    /*** Relayer wrap ETH function                                                              ***/
    /**********************************************************************************************/

    function wrapAllProxyETH() external nonReentrant onlyRole(RELAYER) {
        WrapProxyETHLib.wrapAll(proxy);
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
    /*** Relayer Curve StableSwap functions                                                     ***/
    /**********************************************************************************************/

    function swapCurve(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return CurveLib.swap({
            proxy        : proxy,
            rateLimits   : rateLimits,
            pool         : pool,
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            maxSlippages : maxSlippages
        });
    }

    function addLiquidityCurve(address pool, uint256[] memory depositAmounts, uint256 minLpAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return CurveLib.addLiquidity({
            proxy          : proxy,
            rateLimits     : rateLimits,
            pool           : pool,
            minLpAmount    : minLpAmount,
            depositAmounts : depositAmounts,
            maxSlippages   : maxSlippages
        });
    }

    function removeLiquidityCurve(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256[] memory withdrawnTokens)
    {
        return CurveLib.removeLiquidity({
            proxy              : proxy,
            rateLimits         : rateLimits,
            pool               : pool,
            lpBurnAmount       : lpBurnAmount,
            minWithdrawAmounts : minWithdrawAmounts,
            maxSlippages       : maxSlippages
        });
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
    /*** Uniswap V4 functions                                                                   ***/
    /**********************************************************************************************/

    function mintPositionUniswapV4(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.mintPosition({
            proxy      : proxy,
            rateLimits : rateLimits,
            poolId     : poolId,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            tickLimits : uniswapV4TickLimits
        });
    }

    function increaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.increasePosition({
            proxy             : proxy,
            rateLimits        : rateLimits,
            poolId            : poolId,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max,
            tickLimits        : uniswapV4TickLimits
        });
    }

    function decreaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.decreasePosition({
            proxy             : proxy,
            rateLimits        : rateLimits,
            poolId            : poolId,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });
    }

    function swapUniswapV4(
        bytes32 poolId,
        address tokenIn,
        uint128 amountIn,
        uint128 amountOutMin
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.swap(proxy, rateLimits, poolId, tokenIn, amountIn, amountOutMin, maxSlippages);
    }

    /**********************************************************************************************/
    /*** Relayer Ethena functions                                                               ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner) external nonReentrant onlyRole(RELAYER) {
        USDELib.setDelegatedSigner(proxy, ethenaMinter, delegatedSigner);
    }

    function removeDelegatedSigner(address delegatedSigner)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        USDELib.removeDelegatedSigner(proxy, ethenaMinter, delegatedSigner);
    }

    // Note that Ethena's mint/redeem per-block limits include other users.
    function prepareUSDEMint(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        USDELib.prepareMint(proxy, rateLimits, ethenaMinter, usdcAmount);
    }

    function prepareUSDEBurn(uint256 usdeAmount) external nonReentrant onlyRole(RELAYER) {
        USDELib.prepareBurn(proxy, rateLimits, ethenaMinter, usdeAmount);
    }

    function cooldownAssetsSUSDE(uint256 usdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownShares)
    {
        return USDELib.cooldownAssets(proxy, rateLimits, usdeAmount);
    }

    function cooldownSharesSUSDE(uint256 susdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownAssets)
    {
        return USDELib.cooldownShares(proxy, rateLimits, susdeAmount);
    }

    function unstakeSUSDE() external nonReentrant onlyRole(RELAYER) {
        USDELib.unstakeSUSDE(proxy);
    }

    /**********************************************************************************************/
    /*** Relayer Maple functions                                                                ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MapleLib.requestRedemption(proxy, rateLimits, mapleToken, shares);
    }

    function cancelMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MapleLib.cancelRedemption(proxy, rateLimits, mapleToken, shares);
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
    /*** Relayer Merkl functions                                                                ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address operator)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MerklLib.toggleOperator({
            proxy       : proxy,
            distributor : merklDistributor,
            operator    : operator
        });
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        SuperstateLib.subscribe(proxy, rateLimits, usdcAmount);
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        DAIUSDSLib.swapUSDSToDAI(proxy, usdsAmount);
    }

    function swapDAIToUSDS(uint256 daiAmount) external nonReentrant onlyRole(RELAYER) {
        DAIUSDSLib.swapDAIToUSDS(proxy, daiAmount);
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    function swapUSDSToUSDC(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        PSMLib.swapUSDSToUSDC(proxy, rateLimits, usdcAmount);
    }

    function swapUSDCToUSDS(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        PSMLib.swapUSDCToUSDS(proxy, rateLimits, usdcAmount);
    }

    function psmTo18ConversionFactor() external view returns (uint256) {
        return PSMLib.to18ConversionFactor();
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
    /*** Relayer SPK Farm functions                                                             ***/
    /**********************************************************************************************/

    function depositToFarm(address farm, uint256 amount) external nonReentrant onlyRole(RELAYER) {
        FarmLib.deposit(proxy, rateLimits, farm, amount);
    }

    function withdrawFromFarm(address farm, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        FarmLib.withdraw(proxy, rateLimits, farm, amount);
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
    /*** OTC swap functions                                                                     ***/
    /**********************************************************************************************/

    function otcSend(address exchange, address assetToSend, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        OTCLib.send({
            proxy             : proxy,
            rateLimits        : rateLimits,
            exchange          : exchange,
            assetToSend       : assetToSend,
            amount            : amount,
            whitelistedAssets : otcWhitelistedAssets,
            otcs              : otcs,
            maxSlippages      : maxSlippages
        });
    }

    function otcClaim(address exchange, address assetToClaim)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        OTCLib.claim(proxy, exchange, assetToClaim, otcWhitelistedAssets, otcs);
    }

    function getOTCClaimWithRecharge(address exchange) external view returns (uint256) {
        return OTCLib.getClaimWithRecharge(exchange, otcs);
    }

    function isOTCSwapReady(address exchange) external view returns (bool) {
        return OTCLib.isSwapReady(exchange, otcs, maxSlippages);
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

    // NOTE: These cancelation methods are compatible with ERC-7887

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

    function transferSharesCentrifuge(
        address token,
        uint128 amount,
        uint16  centrifugeId
    )
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
