// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title OrderingPredicates
/// @notice Pure predicates over positions authenticated by Attestcoin.
/// @dev Source-chain history is ordered lexicographically by `(blockHeight, txIndex)`. A position
///      from a different chain key is deliberately incomparable.
library OrderingPredicates {
    struct Position {
        uint64 chainKey;
        uint64 blockHeight;
        uint64 txIndex;
    }

    error DifferentSourceChains(uint64 leftChainKey, uint64 rightChainKey);
    error PositionNotBefore(uint64 leftBlock, uint64 leftIndex, uint64 rightBlock, uint64 rightIndex);
    error SequenceNotAscending(uint256 rightPosition);

    /// @return result `-1` if left is earlier, `0` if equal and `1` if left is later.
    function compare(Position memory left, Position memory right) internal pure returns (int8 result) {
        _requireSameChain(left, right);
        if (left.blockHeight < right.blockHeight) return -1;
        if (left.blockHeight > right.blockHeight) return 1;
        if (left.txIndex < right.txIndex) return -1;
        if (left.txIndex > right.txIndex) return 1;
        return 0;
    }

    function isBefore(Position memory left, Position memory right) internal pure returns (bool) {
        return compare(left, right) < 0;
    }

    function isAfter(Position memory left, Position memory right) internal pure returns (bool) {
        return compare(left, right) > 0;
    }

    function isSamePosition(Position memory left, Position memory right) internal pure returns (bool) {
        return compare(left, right) == 0;
    }

    /// @notice Adjacency is only knowable within one block without also proving the earlier
    ///         block's transaction count.
    function isImmediatelyBeforeInBlock(Position memory left, Position memory right) internal pure returns (bool) {
        _requireSameChain(left, right);
        return
            left.blockHeight == right.blockHeight && left.txIndex != type(uint64).max
                && left.txIndex + 1 == right.txIndex;
    }

    function assertBefore(Position memory left, Position memory right) internal pure {
        if (!isBefore(left, right)) {
            revert PositionNotBefore(left.blockHeight, left.txIndex, right.blockHeight, right.txIndex);
        }
    }

    function assertStrictlyAscending(Position[] memory positions) internal pure {
        for (uint256 i = 1; i < positions.length; ++i) {
            if (!isBefore(positions[i - 1], positions[i])) revert SequenceNotAscending(i);
        }
    }

    function _requireSameChain(Position memory left, Position memory right) private pure {
        if (left.chainKey != right.chainKey) revert DifferentSourceChains(left.chainKey, right.chainKey);
    }
}
