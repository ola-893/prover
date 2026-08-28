// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { INativeQueryVerifier, NativeQueryVerifierLib } from "./INativeQueryVerifier.sol";
import { OrderingPredicates } from "./OrderingPredicates.sol";

/// @title AttestcoinProofAdapter
/// @notice Verifies source-chain transaction history and returns reusable authenticated positions.
/// @dev The verifier is injected so courts and profile adapters can be tested without etching code
///      at the precompile address. Production deployments should use `NativeAttestcoinProofAdapter`.
contract AttestcoinProofAdapter {
    struct BlockContext {
        uint64 chainKey;
        uint64 blockHeight;
        bytes32 lowerEndpointDigest;
        bytes32[] continuityRoots;
    }

    struct TransactionInclusion {
        bytes encodedTransaction;
        bytes32 merkleRoot;
        INativeQueryVerifier.MerkleProofEntry[] siblings;
    }

    struct VerifiedTransaction {
        OrderingPredicates.Position position;
        bytes32 transactionCommitment;
        bytes32 merkleRoot;
        bytes32 evidenceId;
    }

    INativeQueryVerifier public immutable VERIFIER;

    event AttestcoinEvidenceVerified(
        bytes32 indexed evidenceId,
        uint64 indexed chainKey,
        uint64 indexed blockHeight,
        uint64 txIndex,
        bytes32 transactionCommitment,
        bytes32 merkleRoot
    );

    error ZeroVerifier();
    error EmptyBatch();
    error InconsistentMerkleRoot(uint256 inclusion, bytes32 expected, bytes32 actual);
    error VerificationFailed(uint256 inclusion);

    constructor(INativeQueryVerifier verifier_) {
        if (address(verifier_) == address(0)) revert ZeroVerifier();
        VERIFIER = verifier_;
    }

    /// @notice Verifies one transaction and recovers its total-order position on its source chain.
    function verifyTransaction(BlockContext calldata context, TransactionInclusion calldata inclusion)
        external
        returns (VerifiedTransaction memory result)
    {
        result = _verifyTransaction(context, inclusion, 0);
    }

    /// @notice Verifies multiple transactions in one source block with one shared continuity proof.
    /// @dev Each inclusion still requires a separate `verifyAndEmit` call because the native
    ///      verifier has no Solidity batch entry point.
    function verifySameBlockBatch(BlockContext calldata context, TransactionInclusion[] calldata inclusions)
        external
        returns (VerifiedTransaction[] memory results)
    {
        return _verifySameBlockBatch(context, inclusions);
    }

    function _verifySameBlockBatch(BlockContext calldata context, TransactionInclusion[] calldata inclusions)
        internal
        returns (VerifiedTransaction[] memory results)
    {
        uint256 length = inclusions.length;
        if (length == 0) revert EmptyBatch();

        bytes32 commonRoot = inclusions[0].merkleRoot;
        for (uint256 i = 1; i < length; ++i) {
            if (inclusions[i].merkleRoot != commonRoot) {
                revert InconsistentMerkleRoot(i, commonRoot, inclusions[i].merkleRoot);
            }
        }

        results = new VerifiedTransaction[](length);
        for (uint256 i; i < length; ++i) {
            results[i] = _verifyTransaction(context, inclusions[i], i);
        }
    }

    function _verifyTransaction(
        BlockContext calldata context,
        TransactionInclusion calldata inclusion,
        uint256 inclusionNumber
    ) internal returns (VerifiedTransaction memory result) {
        INativeQueryVerifier.MerkleProof memory merkleProof = INativeQueryVerifier.MerkleProof({
            root: inclusion.merkleRoot, siblings: inclusion.siblings
        });
        INativeQueryVerifier.ContinuityProof memory continuityProof = INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: context.lowerEndpointDigest, roots: context.continuityRoots
        });

        bool verified = VERIFIER.verifyAndEmit(
            context.chainKey, context.blockHeight, inclusion.encodedTransaction, merkleProof, continuityProof
        );
        if (!verified) revert VerificationFailed(inclusionNumber);

        uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);
        bytes32 transactionCommitment = keccak256(inclusion.encodedTransaction);
        bytes32 evidenceId = keccak256(
            abi.encode(context.chainKey, context.blockHeight, txIndex, transactionCommitment, inclusion.merkleRoot)
        );

        result = VerifiedTransaction({
            position: OrderingPredicates.Position({
                chainKey: context.chainKey, blockHeight: context.blockHeight, txIndex: txIndex
            }),
            transactionCommitment: transactionCommitment,
            merkleRoot: inclusion.merkleRoot,
            evidenceId: evidenceId
        });

        emit AttestcoinEvidenceVerified(
            evidenceId, context.chainKey, context.blockHeight, txIndex, transactionCommitment, inclusion.merkleRoot
        );
    }
}

/// @title NativeAttestcoinProofAdapter
/// @notice Production adapter fixed to Creditcoin's Attestcoin verifier precompile at `0x...0FD2`.
contract NativeAttestcoinProofAdapter is AttestcoinProofAdapter {
    constructor() AttestcoinProofAdapter(NativeQueryVerifierLib.getVerifier()) { }
}
