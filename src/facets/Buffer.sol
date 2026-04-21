// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Address } from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import { IBuffer } from "./IBuffer.sol";

contract Buffer is IBuffer {

    using Address for address;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public admin;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyAdmin() {
        require(msg.sender == admin, NotAdmin(msg.sender, admin));
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor() {
        admin = msg.sender;
    }

    /**********************************************************************************************/
    /*** External Interactive Controller Functions                                              ***/
    /**********************************************************************************************/

    function doCall(address target, bytes calldata data)
        external
        override
        onlyAdmin
        returns (bytes memory result)
    {
        return target.functionCall(data);
    }

    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        override
        onlyAdmin
        returns (bytes memory result)
    {
        return target.functionCallWithValue(data, value);
    }

    function doDelegateCall(address target, bytes calldata data)
        external
        override
        onlyAdmin
        returns (bytes memory result)
    {
        return target.functionDelegateCall(data);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

}
