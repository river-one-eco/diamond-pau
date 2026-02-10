// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IUSTBLike {

    function subscribe(uint256 inAmount, address stablecoin) external;

}

library SuperstateLib {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function subscribe(address proxy, address rateLimits, uint256 usdcAmount) external {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_SUBSCRIBE, usdcAmount);

        ApproveLib.approve(Ethereum.USDC, proxy, Ethereum.USTB, usdcAmount);

        IALMProxy(proxy).doCall(
            Ethereum.USTB,
            abi.encodeCall(IUSTBLike.subscribe, (usdcAmount, Ethereum.USDC))
        );
    }

}
