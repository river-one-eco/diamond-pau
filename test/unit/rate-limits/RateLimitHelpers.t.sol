// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { makeAddressKey, makeAddressAddressKey, makeUint32Key } from "../../../src/RateLimitHelpers.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract RateLimitHelpers_Tests is Test {

    bytes32 internal constant KEY  = "KEY";
    string  internal constant NAME = "NAME";

    function test_makeAddressKey() external view {
        assertEq(
            makeAddressKey(KEY, address(this)),
            keccak256(abi.encode(KEY, address(this)))
        );
    }

    function test_makeAddressAddressKey() external view {
        assertEq(
            makeAddressAddressKey(KEY, address(this), address(0)),
            keccak256(abi.encode(KEY, address(this), address(0)))
        );
    }

    function test_makeUint32Key() external view {
        assertEq(
            makeUint32Key(KEY, 123),
            keccak256(abi.encode(KEY, 123))
        );
    }

}
