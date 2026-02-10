// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy } from "../interfaces/IALMProxy.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IDAIUSDSLike {

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

library DAIUSDSLib {

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(address proxy, uint256 usdsAmount) external {
        ApproveLib.approve(Ethereum.USDS, proxy, Ethereum.DAI_USDS, usdsAmount);

        IALMProxy(proxy).doCall(
            Ethereum.DAI_USDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );
    }

    function swapDAIToUSDS(address proxy, uint256 daiAmount) external {
        ApproveLib.approve(Ethereum.DAI, proxy, Ethereum.DAI_USDS, daiAmount);

        IALMProxy(proxy).doCall(
            Ethereum.DAI_USDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

}
