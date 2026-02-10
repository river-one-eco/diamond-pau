// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

interface IDAIUSDSLike {

    function dai() external view returns (address);

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

    function balanceOf(address account) external view returns (uint256 balance);

}

interface IPSMLike {

    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);

    function fill() external returns (uint256 wad);

    function sellGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);

    function to18ConversionFactor() external view returns (uint256);

}

library PSMLib {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_USDS_TO_USDC = keccak256("LIMIT_USDS_TO_USDC");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function swapUSDSToUSDC(
        address proxy,
        address rateLimits,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_USDS_TO_USDC, usdcAmount);

        uint256 usdsAmount = usdcAmount * to18ConversionFactor();

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS).
        _approve(Ethereum.USDS, proxy, Ethereum.DAI_USDS, usdsAmount);

        // Swap USDS to DAI 1:1
        IALMProxy(proxy).doCall(
            Ethereum.DAI_USDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1.
        _approve(Ethereum.DAI, proxy, Ethereum.PSM, usdsAmount);

        // Swap DAI to USDC through the PSM.
        IALMProxy(proxy).doCall(
            Ethereum.PSM,
            abi.encodeCall(IPSMLike.buyGemNoFee, (proxy, usdcAmount))
        );
    }

    function swapUSDCToUSDS(
        address proxy,
        address rateLimits,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitIncrease(LIMIT_USDS_TO_USDC, usdcAmount);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC).
        _approve(Ethereum.USDC, proxy, Ethereum.PSM, usdcAmount);

        uint256 conversionFactor = to18ConversionFactor();
        uint256 daiAmount        = usdcAmount * conversionFactor;

        // Swap all if amount is less than or equal to the max USDC that can be swapped to DAI in
        // one call, else refill and swap in chunks within the limits.
        if (usdcAmount <= IERC20Like(Ethereum.DAI).balanceOf(Ethereum.PSM) / conversionFactor) {
            _swapUSDCToDAI(proxy, Ethereum.PSM, usdcAmount);
        } else {
            // Refill the PSM with DAI as many times as needed to get to the full `usdcAmount`.
            // If the PSM cannot be filled with the full amount, psm.fill() will revert with
            // `DssLitePsm/nothing-to-fill` since rush() will return 0. This is desired behavior
            // because this function should only succeed if the full `usdcAmount` can be swapped.
            while (usdcAmount > 0) {
                IPSMLike(Ethereum.PSM).fill();

                // Max USDC that can be swapped to DAI in one call/fill.
                uint256 limit = IERC20Like(Ethereum.DAI).balanceOf(Ethereum.PSM) / conversionFactor;

                uint256 swapAmount = usdcAmount <= limit ? usdcAmount : limit;

                _swapUSDCToDAI(proxy, Ethereum.PSM, swapAmount);

                usdcAmount -= swapAmount;
            }
        }

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI).
        _approve(Ethereum.DAI, proxy, Ethereum.DAI_USDS, daiAmount);

        // Swap DAI to USDS 1:1.
        IALMProxy(proxy).doCall(
            Ethereum.DAI_USDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** External view/pure functions                                                           ***/
    /**********************************************************************************************/

    function to18ConversionFactor() public view returns (uint256) {
        return IPSMLike(Ethereum.PSM).to18ConversionFactor();
    }

    /**********************************************************************************************/
    /*** Internal interactive functions                                                         ***/
    /**********************************************************************************************/

    // NOTE: As swaps are only done between USDC and USDS, no need for `ApproveLib`.
    function _approve(address token, address proxy, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _swapUSDCToDAI(address proxy, address psm, uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used).
        IALMProxy(proxy).doCall(
            psm,
            abi.encodeCall(IPSMLike.sellGemNoFee, (address(proxy), usdcAmount))
        );
    }

}
