// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AttestcoinProofAdapter, NativeAttestcoinProofAdapter } from "../src/attestcoin/AttestcoinProofAdapter.sol";
import { INativeQueryVerifier } from "../src/attestcoin/INativeQueryVerifier.sol";
import { OrderingPredicates } from "../src/attestcoin/OrderingPredicates.sol";
import { MockNativeQueryVerifier } from "./mocks/MockNativeQueryVerifier.sol";
import { TestBase } from "./TestBase.sol";

contract AttestcoinProofAdapterTest is TestBase {
    bytes32 private constant ROOT = keccak256("ordering-proof:block-25764741:tx-root");

    MockNativeQueryVerifier private verifier;
    AttestcoinProofAdapter private adapter;

    function setUp() public {
        verifier = new MockNativeQueryVerifier();
        adapter = new AttestcoinProofAdapter(verifier);
    }

    function test_LateralityRecovers14Then15Then16() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            new AttestcoinProofAdapter.TransactionInclusion[](3);
        inclusions[0] = _inclusion(hex"aa", "RLLLRRRR", ROOT);
        inclusions[1] = _inclusion(hex"bb", "LLLLRRRR", ROOT);
        inclusions[2] = _inclusion(hex"cc", "RRRRLRRR", ROOT);

        for (uint256 i; i < inclusions.length; ++i) {
            _allow(context, inclusions[i]);
        }

        AttestcoinProofAdapter.VerifiedTransaction[] memory proven = adapter.verifySameBlockBatch(context, inclusions);

        assertEq(proven[0].position.txIndex, 14);
        assertEq(proven[1].position.txIndex, 15);
        assertEq(proven[2].position.txIndex, 16);
        assertTrue(OrderingPredicates.isBefore(proven[0].position, proven[1].position));
        assertTrue(OrderingPredicates.isBefore(proven[1].position, proven[2].position));

        OrderingPredicates.Position[] memory positions = new OrderingPredicates.Position[](3);
        positions[0] = proven[0].position;
        positions[1] = proven[1].position;
        positions[2] = proven[2].position;
        OrderingPredicates.assertStrictlyAscending(positions);
        assertEq(verifier.verificationCalls(), 3);
    }

    function test_TamperedTransactionBytesFailVerification() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion memory original = _inclusion(hex"aabbcc", "RLLLRRRR", ROOT);
        _allow(context, original);

        original.encodedTransaction = hex"aabbcd";
        vm.expectRevert(abi.encodeWithSelector(AttestcoinProofAdapter.VerificationFailed.selector, uint256(0)));
        adapter.verifyTransaction(context, original);
    }

    function test_TamperedMerkleLateralityFailsVerification() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion memory original = _inclusion(hex"aabbcc", "RLLLRRRR", ROOT);
        _allow(context, original);

        original.siblings[0].isLeft = true;
        vm.expectRevert(abi.encodeWithSelector(AttestcoinProofAdapter.VerificationFailed.selector, uint256(0)));
        adapter.verifyTransaction(context, original);
    }

    function test_ExplicitFalseFromVerifierFailsClosed() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion memory inclusion = _inclusion(hex"aa", "RLLLRRRR", ROOT);
        _allow(context, inclusion);
        verifier.setForceFalse(true);

        vm.expectRevert(abi.encodeWithSelector(AttestcoinProofAdapter.VerificationFailed.selector, uint256(0)));
        adapter.verifyTransaction(context, inclusion);
    }

    function test_VerifierRevertBubblesAndNoEvidenceIsReturned() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion memory inclusion = _inclusion(hex"aa", "RLLLRRRR", ROOT);
        _allow(context, inclusion);
        verifier.setForceRevert(true);

        vm.expectRevert(MockNativeQueryVerifier.MockVerificationReverted.selector);
        adapter.verifyTransaction(context, inclusion);
    }

    function test_SameBlockBatchRejectsDifferentMerkleRoots() public {
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            new AttestcoinProofAdapter.TransactionInclusion[](2);
        inclusions[0] = _inclusion(hex"aa", "RLLLRRRR", ROOT);
        inclusions[1] = _inclusion(hex"bb", "LLLLRRRR", keccak256("other-root"));

        vm.expectRevert(
            abi.encodeWithSelector(
                AttestcoinProofAdapter.InconsistentMerkleRoot.selector, uint256(1), ROOT, keccak256("other-root")
            )
        );
        adapter.verifySameBlockBatch(_context(), inclusions);
    }

    function test_EmptyBatchFails() public {
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            new AttestcoinProofAdapter.TransactionInclusion[](0);
        vm.expectRevert(AttestcoinProofAdapter.EmptyBatch.selector);
        adapter.verifySameBlockBatch(_context(), inclusions);
    }

    function test_EvidenceIdentityBindsPositionBytesAndRoot() public {
        AttestcoinProofAdapter.BlockContext memory context = _context();
        AttestcoinProofAdapter.TransactionInclusion memory inclusion = _inclusion(hex"aabbcc", "RLLLRRRR", ROOT);
        _allow(context, inclusion);

        AttestcoinProofAdapter.VerifiedTransaction memory proven = adapter.verifyTransaction(context, inclusion);
        bytes32 expectedCommitment = keccak256(hex"aabbcc");
        bytes32 expectedId = keccak256(abi.encode(uint64(3), uint64(25_764_741), uint64(14), expectedCommitment, ROOT));

        assertEq(proven.transactionCommitment, expectedCommitment);
        assertEq(proven.evidenceId, expectedId);
        assertEq(proven.merkleRoot, ROOT);
    }

    function test_ConstructorRejectsZeroVerifier() public {
        vm.expectRevert(AttestcoinProofAdapter.ZeroVerifier.selector);
        new AttestcoinProofAdapter(INativeQueryVerifier(address(0)));
    }

    function test_NativeAdapterUsesCreditcoinPrecompile() public {
        NativeAttestcoinProofAdapter native = new NativeAttestcoinProofAdapter();
        assertEq(address(native.VERIFIER()), 0x0000000000000000000000000000000000000FD2);
    }

    function _context() private pure returns (AttestcoinProofAdapter.BlockContext memory context) {
        context.chainKey = 3;
        context.blockHeight = 25_764_741;
        context.lowerEndpointDigest = keccak256("lower-endpoint");
        context.continuityRoots = new bytes32[](2);
        context.continuityRoots[0] = keccak256("continuity-0");
        context.continuityRoots[1] = keccak256("continuity-1");
    }

    function _inclusion(bytes memory encodedTransaction, bytes memory pattern, bytes32 root)
        private
        pure
        returns (AttestcoinProofAdapter.TransactionInclusion memory inclusion)
    {
        inclusion.encodedTransaction = encodedTransaction;
        inclusion.merkleRoot = root;
        inclusion.siblings = new INativeQueryVerifier.MerkleProofEntry[](pattern.length);
        for (uint256 i; i < pattern.length; ++i) {
            inclusion.siblings[i] = INativeQueryVerifier.MerkleProofEntry({
                hash: keccak256(abi.encode("sibling", i)), isLeft: pattern[i] == "L"
            });
        }
    }

    function _allow(
        AttestcoinProofAdapter.BlockContext memory context,
        AttestcoinProofAdapter.TransactionInclusion memory inclusion
    ) private {
        INativeQueryVerifier.MerkleProof memory
            merkleProof = INativeQueryVerifier.MerkleProof({ root: inclusion.merkleRoot, siblings: inclusion.siblings });
        INativeQueryVerifier.ContinuityProof memory continuityProof = INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: context.lowerEndpointDigest, roots: context.continuityRoots
        });
        verifier.allowProof(
            context.chainKey, context.blockHeight, inclusion.encodedTransaction, merkleProof, continuityProof
        );
    }
}
