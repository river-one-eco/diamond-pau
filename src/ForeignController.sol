// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { PSM3Lib }          from "./libraries/PSM3Lib.sol";
import { SparkVaultLib }    from "./libraries/SparkVaultLib.sol";
import { TransferAssetLib } from "./libraries/TransferAssetLib.sol";

contract ForeignController is ReentrancyGuard, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** Roles                                                                                  ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Rate Limits Keys                                                                       ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_4626_DEPOSIT       = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_4626_WITHDRAW      = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_AAVE_DEPOSIT       = AaveLib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_AAVE_WITHDRAW      = AaveLib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_ASSET_TRANSFER     = TransferAssetLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_PSM_DEPOSIT        = PSM3Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_PSM_WITHDRAW       = PSM3Lib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_SPARK_VAULT_TAKE   = SparkVaultLib.LIMIT_TAKE;
    bytes32 public constant LIMIT_USDC_TO_CCTP       = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public constant LIMIT_USDC_TO_DOMAIN     = CCTPLib.LIMIT_TO_DOMAIN;

    /**********************************************************************************************/
    /*** Controller State Variables                                                             ***/
    /**********************************************************************************************/

    address public immutable proxy;
    address public immutable rateLimits;

    /**********************************************************************************************/
    /*** Integration-Specific State Variables                                                   ***/
    /**********************************************************************************************/

    address public psm3;

    address public cctpTokenMessenger;
    address public cctpUSDC;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

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

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
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

    function setPSM3(address psm) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        psm3 = psm;
    }

    function setCCTPTokenMessenger(address messenger) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        cctpTokenMessenger = messenger;
    }

    function setCCTPUSDC(address usdc) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        cctpUSDC = usdc;
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
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        SparkVaultLib.take(proxy, rateLimits, sparkVault, assetAmount);
    }

}
