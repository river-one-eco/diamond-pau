// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Address } from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import { IBuffer } from "./IBuffer.sol";

contract Buffer is IBuffer {

    using Address for address;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IBuffer
    address public immutable owner;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyOwner() {
        require(msg.sender == owner, NotOwner(msg.sender, owner));
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address owner_) {
        owner = owner_;
    }

    /**********************************************************************************************/
    /*** External Interactive Controller Functions                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IBuffer
    function doCall(address target, bytes calldata data)
        external
        override
        onlyOwner
        returns (bytes memory result)
    {
        return target.functionCall(data);
    }

    /// @inheritdoc IBuffer
    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        override
        onlyOwner
        returns (bytes memory result)
    {
        return target.functionCallWithValue(data, value);
    }

    /// @inheritdoc IBuffer
    function doDelegateCall(address target, bytes calldata data)
        external
        override
        onlyOwner
        returns (bytes memory result)
    {
        return target.functionDelegateCall(data);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

}
