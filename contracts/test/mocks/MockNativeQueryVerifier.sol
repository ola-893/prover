// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/*
 * The laterality decoder and mock-boundary approach include portions adapted from software
 * Copyright (c) 2026 Edy Cu. Used under the MIT License reproduced in
 * contracts/src/attestcoin/EDY_CU_MIT_NOTICE.md.
 */

import { INativeQueryVerifier } from "../../src/attestcoin/INativeQueryVerifier.sol";

/// @notice Deterministic unit-test boundary. A proof is accepted only when its complete calldata
///         commitment has been explicitly allowlisted before the call.
contract MockNativeQueryVerifier is INativeQueryVerifier {
    mapping(bytes32 commitment => bool accepted) public acceptedProofs;

    bool public forceFalse;
    bool public forceRevert;
    uint256 public verificationCalls;

    event TransactionVerified(uint64 indexed chainKey, uint64 indexed height, uint64 indexed txIndex);

    error MockVerificationReverted();

    function allowProof(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external {
        acceptedProofs[_proofCommitment(chainKey, height, encodedTransaction, merkleProof, continuityProof)] = true;
    }

    function setForceFalse(bool value) external {
        forceFalse = value;
    }

    function setForceRevert(bool value) external {
        forceRevert = value;
    }

    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external returns (bool) {
        ++verificationCalls;
        if (forceRevert) revert MockVerificationReverted();
        if (forceFalse) return false;

        bool accepted =
            acceptedProofs[_proofCommitment(chainKey, height, encodedTransaction, merkleProof, continuityProof)];
        if (accepted) emit TransactionVerified(chainKey, height, _indexFromLaterality(merkleProof.siblings));
        return accepted;
    }

    function calculateTxIndex(MerkleProof calldata merkleProof) external pure returns (uint64) {
        return _indexFromLaterality(merkleProof.siblings);
    }

    function _proofCommitment(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(chainKey, height, encodedTransaction, merkleProof, continuityProof));
    }

    /// @dev Leaf-to-root, least-significant bit first. A sibling on the left means the proven
    ///      node occupied the right branch, so the corresponding index bit is one.
    function _indexFromLaterality(MerkleProofEntry[] calldata siblings) private pure returns (uint64 index) {
        uint64 bit = 1;
        for (uint256 i; i < siblings.length; ++i) {
            if (siblings[i].isLeft) index |= bit;
            if (bit > type(uint64).max / 2) break;
            bit <<= 1;
        }
    }
}
