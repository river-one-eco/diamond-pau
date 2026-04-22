// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { WEETHBuffer } from "../../src/facets/weeth/WEETHBuffer.sol";

abstract contract WEETHModule_TestBase is Test {

    /**********************************************************************************************/
    /*** onERC721Received Tests                                                                 ***/
    /**********************************************************************************************/

    function test_onERC721Received() external {
        WEETHBuffer buffer = new WEETHBuffer(address(0));

        assertEq(
            buffer.onERC721Received(address(0), address(0), 1, ""),
            buffer.onERC721Received.selector
        );

        assertEq(
            buffer.onERC721Received(address(1), address(1), 1, "0xdead"),
            buffer.onERC721Received.selector
        );
    }

}
