// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Ethereum as GroveEthereum } from "../../lib/grove-address-registry/src/Ethereum.sol";
import { Ethereum as SparkEthereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IMerklDistributorLike {

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);

    function operators(address user, address operator) external view returns (uint256);

    function claim(
        address[]   calldata users,
        address[]   calldata tokens,
        uint256[]   calldata amounts,
        bytes32[][] calldata proofs
    ) external;

}

abstract contract Merkl_BaseTest is ForkTestBase {

    address internal constant A_ETH_RLUSD = 0x72eEED8043Dcce2Fe7CdAC950D928F80f472ab80;

    address internal operator1 = makeAddr("operator1");
    address internal operator2 = makeAddr("operator2");

    IMerklDistributorLike internal constant MERKL_DISTRIBUTOR = IMerklDistributorLike(GroveEthereum.MERKL_DISTRIBUTOR);

    function _getBlock() internal pure override returns (uint256) {
        return 23827450;  // Nov 18, 2025
    }
}

contract MainnetController_Merkl_ToggleOperator_Tests is Merkl_BaseTest {

    function setUp() public override {
        super.setUp();

        vm.prank(SparkEthereum.SPARK_PROXY);
        mainnetController.setMerklDistributor(GroveEthereum.MERKL_DISTRIBUTOR);
    }

    function test_toggleOperatorMerkl_merklDistributorNotSet() external {
        vm.prank(SparkEthereum.SPARK_PROXY);
        mainnetController.setMerklDistributor(address(0));

        vm.expectRevert("MerklLib/merkl-distributor-not-set");

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);
    }

    function test_toggleOperatorMerkl_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.toggleOperatorMerkl(operator1);
    }

    function test_toggleOperatorMerkl_singleOperator() external {
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 0);

        vm.expectEmit(GroveEthereum.MERKL_DISTRIBUTOR);
        emit IMerklDistributorLike.OperatorToggled(almProxy, operator1, true);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 1);

        vm.expectEmit(GroveEthereum.MERKL_DISTRIBUTOR);
        emit IMerklDistributorLike.OperatorToggled(almProxy, operator1, false);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 0);

        vm.expectEmit(GroveEthereum.MERKL_DISTRIBUTOR);
        emit IMerklDistributorLike.OperatorToggled(almProxy, operator1, true);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 1);
    }

    function test_toggleOperatorMerkl_multipleOperators() external {
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 0);
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator2), 0);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 1);
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator2), 0);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 0);
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator2), 0);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 1);
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator2), 0);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator2);

        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator1), 1);
        assertEq(MERKL_DISTRIBUTOR.operators(almProxy, operator2), 1);
    }

    function test_toggleOperatorMerkl_attemptClaim() external {
        address[]   memory users   = new address[](1);
        address[]   memory tokens  = new address[](1);
        uint256[]   memory amounts = new uint256[](1);
        bytes32[][] memory proofs  = new bytes32[][](1);

        users[0]     = almProxy;
        tokens[0]    = A_ETH_RLUSD;
        amounts[0]   = 299_033.458789039331965803e18;
        proofs[0]    = new bytes32[](1);
        proofs[0][0] = bytes32(0);

        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        vm.prank(operator1);
        MERKL_DISTRIBUTOR.claim(users, tokens, amounts, proofs);

        vm.prank(RELAYER);
        mainnetController.toggleOperatorMerkl(operator1);

        // Hitting the InvalidProof() error proves that we are whitelisted as operator1
        // (https://github.com/AngleProtocol/merkl-contracts/blob/e4c49c1fbfb274029d31969adf70ca6aeec689f0/contracts/Distributor.sol#L378-L383)
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        vm.prank(operator1);
        MERKL_DISTRIBUTOR.claim(users, tokens, amounts, proofs);
    }

}
