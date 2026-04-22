// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IBuffer } from "../IBuffer.sol";

/**
 * @title  IWEETHBuffer
 * @notice Interface for the WEETHBuffer contract, exposing the `onERC721Received` function.
 */
interface IWEETHBuffer is IBuffer {

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Receives an ERC721 token.
     * @param  operator Operator address.
     * @param  from     From address.
     * @param  tokenId  Token ID.
     * @param  data     Data.
     * @return selector Selector response.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        returns (bytes4 selector);

}
