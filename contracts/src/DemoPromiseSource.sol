// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title DemoPromiseSource
/// @notice Minimal source-chain event emitter for end-to-end RFQ and settlement demonstrations.
/// @dev Each `(actor, promise)` and `(actor, reference)` can be emitted only once, preventing an
///      unrelated caller from consuming another actor's identifiers. This fixture records positive
///      history; it does not custody or transfer assets.
contract DemoPromiseSource {
    mapping(address actor => mapping(bytes32 referenceId => bool emitted)) public referenceEmitted;
    mapping(address actor => mapping(bytes32 promiseId => bool emitted)) public promiseEmitted;

    event RFQExecuted(
        bytes32 indexed promiseId,
        bytes32 indexed quoteId,
        address indexed actor,
        address beneficiary,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient
    );
    event SettlementReleased(
        bytes32 indexed promiseId,
        bytes32 indexed settlementId,
        address indexed actor,
        address asset,
        address recipient,
        uint256 amount
    );

    error ZeroPromiseId();
    error ZeroReferenceId();
    error ReferenceAlreadyEmitted(bytes32 referenceId);
    error PromiseAlreadyEmitted(bytes32 promiseId);

    function executeRfq(
        bytes32 promiseId,
        bytes32 quoteId,
        address beneficiary,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        address recipient
    ) external {
        _consumeReference(promiseId, quoteId);
        emit RFQExecuted(
            promiseId, quoteId, msg.sender, beneficiary, inputToken, outputToken, inputAmount, outputAmount, recipient
        );
    }

    function releaseSettlement(
        bytes32 promiseId,
        bytes32 settlementId,
        address asset,
        address recipient,
        uint256 amount
    ) external {
        _consumeReference(promiseId, settlementId);
        emit SettlementReleased(promiseId, settlementId, msg.sender, asset, recipient, amount);
    }

    function _consumeReference(bytes32 promiseId, bytes32 referenceId) private {
        if (promiseId == bytes32(0)) revert ZeroPromiseId();
        if (referenceId == bytes32(0)) revert ZeroReferenceId();
        if (promiseEmitted[msg.sender][promiseId]) revert PromiseAlreadyEmitted(promiseId);
        if (referenceEmitted[msg.sender][referenceId]) revert ReferenceAlreadyEmitted(referenceId);
        promiseEmitted[msg.sender][promiseId] = true;
        referenceEmitted[msg.sender][referenceId] = true;
    }
}
