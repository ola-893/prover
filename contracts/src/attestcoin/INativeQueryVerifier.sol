// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/*
 * Portions adapted from software Copyright (c) 2026 Edy Cu.
 * Used under the MIT License reproduced in EDY_CU_MIT_NOTICE.md.
 */

/// @title INativeQueryVerifier
/// @notice Attestcoin's native transaction-inclusion verifier on Creditcoin.
/// @dev Solidity has no on-chain batch method. Call `verifyAndEmit` once per transaction, reusing
///      a continuity proof when the transactions share a source block.
interface INativeQueryVerifier {
    struct MerkleProofEntry {
        bytes32 hash;
        bool isLeft;
    }

    struct MerkleProof {
        bytes32 root;
        MerkleProofEntry[] siblings;
    }

    struct ContinuityProof {
        bytes32 lowerEndpointDigest;
        bytes32[] roots;
    }

    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external returns (bool);

    /// @notice Recovers the transaction's ordinal position from Merkle-path laterality.
    function calculateTxIndex(MerkleProof calldata merkleProof) external view returns (uint64);
}

library NativeQueryVerifierLib {
    /// @notice Attestcoin block-prover precompile, address 4050 decimal.
    address internal constant PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000FD2;

    function getVerifier() internal pure returns (INativeQueryVerifier verifier) {
        verifier = INativeQueryVerifier(PRECOMPILE_ADDRESS);
    }
}
