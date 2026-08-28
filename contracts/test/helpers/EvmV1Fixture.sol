// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { EvmV1Decoder } from "../../src/attestcoin/EvmV1Decoder.sol";

/// @notice Minimal encoder for valid Type-2 transaction fixtures consumed by EvmV1Decoder.
library EvmV1Fixture {
    function encodeType2(address from, address to, uint8 receiptStatus, EvmV1Decoder.LogEntryTuple[] memory receiptLogs)
        internal
        pure
        returns (bytes memory encodedTransaction)
    {
        return encodeType2WithCall(from, to, 0, bytes(""), receiptStatus, receiptLogs);
    }

    function encodeType2WithCall(
        address from,
        address to,
        uint64 nonce,
        bytes memory callData,
        uint8 receiptStatus,
        EvmV1Decoder.LogEntryTuple[] memory receiptLogs
    ) internal pure returns (bytes memory encodedTransaction) {
        return encodeType2WithCallAndValue(from, to, nonce, callData, 0, receiptStatus, receiptLogs);
    }

    function encodeType2WithCallAndValue(
        address from,
        address to,
        uint64 nonce,
        bytes memory callData,
        uint256 value,
        uint8 receiptStatus,
        EvmV1Decoder.LogEntryTuple[] memory receiptLogs
    ) internal pure returns (bytes memory encodedTransaction) {
        bytes[] memory chunks = new bytes[](3);

        chunks[0] = abi.encode(
            nonce,
            uint64(1_000_000), // gas limit
            from,
            false, // to is not null
            to,
            value,
            callData
        );

        EvmV1Decoder.AccessListEntryBytes32[] memory accessList = new EvmV1Decoder.AccessListEntryBytes32[](0);
        chunks[1] = abi.encode(
            uint64(1), // chain id
            uint128(1 gwei), // max priority fee per gas
            uint128(2 gwei), // max fee per gas
            accessList,
            uint8(0), // y parity
            bytes32(uint256(1)), // r
            bytes32(uint256(2)) // s
        );

        chunks[2] = abi.encode(
            receiptStatus,
            uint64(100_000), // receipt gas used
            receiptLogs,
            bytes("") // logs bloom is not used by the court fixtures
        );

        encodedTransaction = abi.encode(uint8(2), chunks);
    }
}
