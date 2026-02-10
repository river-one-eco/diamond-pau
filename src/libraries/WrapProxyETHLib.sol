// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy } from "../interfaces/IALMProxy.sol";

library WrapProxyETHLib {

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function wrapAll(address proxy) external {
        if (proxy.balance == 0) return;

        IALMProxy(proxy).doCallWithValue(Ethereum.WETH, "", proxy.balance);
    }

}
