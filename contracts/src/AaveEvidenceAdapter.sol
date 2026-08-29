// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PerformanceBureau } from "./PerformanceBureau.sol";
import { AttestcoinProofAdapter } from "./attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "./attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";
import { OrderingPredicates } from "./attestcoin/OrderingPredicates.sol";

/// @title AaveEvidenceAdapter
/// @notice Turns authenticated Ethereum Aave V3 USDC receipt logs into narrowly stated bureau facts.
/// @dev A linked observation means only that Aave emitted a USDC Borrow for a subject and, at least
///      32 source blocks later, emitted a same-or-larger self-funded Repay reducing that subject's
///      debt. Aave positions have no per-loan identifier, and Repay has no interest-rate-mode field,
///      so this contract does not certify a linked loan, full repayment, timeliness, a current
///      balance, liquidation absence, or a complete credit history.
contract AaveEvidenceAdapter is AttestcoinProofAdapter {
    uint64 public constant ETHEREUM_MAINNET_CHAIN_KEY = 3;
    uint64 public constant MINIMUM_SELF_REPAYMENT_BLOCK_GAP = 32;

    address public constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 public constant AAVE_BORROW = keccak256("Borrow(address,address,address,uint256,uint8,uint256,uint16)");
    bytes32 public constant AAVE_REPAY = keccak256("Repay(address,address,address,uint256,bool)");

    uint256 private constant AAVE_EVENT_TOPICS = 4;
    uint256 private constant BORROW_DATA_LENGTH = 128;
    uint256 private constant REPAY_DATA_LENGTH = 64;

    enum FactKind {
        NONE,
        BORROW,
        REPAY
    }

    struct AaveFact {
        FactKind kind;
        address subject;
        address actor;
        address reserve;
        uint128 amount;
        uint64 receiptLogOrdinal;
        uint8 interestRateMode;
        bool useATokens;
        OrderingPredicates.Position position;
        bytes32 transactionEvidenceId;
    }

    struct SelfRepaymentObservation {
        address subject;
        bytes32 borrowFactId;
        bytes32 repayFactId;
        uint128 matchedAmount;
        uint64 sourceBlockGap;
    }

    PerformanceBureau public immutable PERFORMANCE_BUREAU;

    mapping(bytes32 factId => AaveFact fact) private _facts;
    mapping(bytes32 factId => bool used) public factUsedInObservation;
    mapping(bytes32 observationId => SelfRepaymentObservation observation) private _observations;

    event AaveFactRecorded(
        bytes32 indexed factId,
        bytes32 indexed transactionEvidenceId,
        FactKind indexed kind,
        address subject,
        address actor,
        address reserve,
        uint128 amount,
        uint64 sourceBlock,
        uint64 sourceTxIndex,
        uint64 receiptLogOrdinal
    );
    event VerifiedSelfRepaymentLinked(
        bytes32 indexed observationId,
        bytes32 indexed borrowFactId,
        bytes32 indexed repayFactId,
        address subject,
        uint128 matchedAmount,
        uint64 sourceBlockGap
    );

    error ZeroAddress();
    error WrongSourceChain(uint64 expected, uint64 actual);
    error UnsupportedTransactionType(uint8 txType);
    error SourceTransactionReverted(uint8 receiptStatus);
    error ReceiptLogOrdinalOutOfBounds(uint256 ordinal, uint256 logCount);
    error ReceiptLogOrdinalDoesNotFit(uint256 ordinal);
    error WrongEmitter(address expected, address actual);
    error UnsupportedAaveEvent(bytes32 eventSignature);
    error MalformedEvent(bytes32 eventSignature, uint256 topicCount, uint256 dataLength);
    error MalformedIndexedAddress(bytes32 topic);
    error UnsupportedReserve(address reserve);
    error UnsupportedInterestRateMode(uint8 interestRateMode);
    error InvalidSubject();
    error AmountDoesNotFit(uint256 amount);
    error FactAlreadyRecorded(bytes32 factId);
    error FactNotFound(bytes32 factId);
    error WrongFactKind(bytes32 factId, FactKind expected, FactKind actual);
    error SubjectMismatch(address borrowSubject, address repaySubject);
    error ReserveMismatch(address borrowReserve, address repayReserve);
    error RepaymentNotSelfFunded(address subject, address repayer);
    error RepaymentNotAfterBorrow(uint64 borrowBlock, uint64 repayBlock);
    error SourceBlockGapTooSmall(uint64 minimum, uint64 actual);
    error RepaymentAmountTooSmall(uint128 borrowAmount, uint128 repayAmount);
    error FactAlreadyUsed(bytes32 factId);

    constructor(INativeQueryVerifier verifier_, PerformanceBureau performanceBureau_)
        AttestcoinProofAdapter(verifier_)
    {
        if (address(performanceBureau_) == address(0)) revert ZeroAddress();
        PERFORMANCE_BUREAU = performanceBureau_;
    }

    function factOf(bytes32 factId) external view returns (AaveFact memory) {
        return _facts[factId];
    }

    function observationOf(bytes32 observationId) external view returns (SelfRepaymentObservation memory) {
        return _observations[observationId];
    }

    /// @notice Authenticates a receipt and records the Aave Borrow or Repay at one exact log ordinal.
    /// @dev Non-Aave logs are rejected instead of searched past, binding the fact ID to an exact
    ///      receipt position even when one transaction emits several otherwise identical events.
    function ingestAaveFact(
        BlockContext calldata context,
        TransactionInclusion calldata inclusion,
        uint256 receiptLogOrdinal
    ) external returns (bytes32 factId) {
        if (context.chainKey != ETHEREUM_MAINNET_CHAIN_KEY) {
            revert WrongSourceChain(ETHEREUM_MAINNET_CHAIN_KEY, context.chainKey);
        }

        VerifiedTransaction memory verified = _verifyTransaction(context, inclusion, 0);
        EvmV1Decoder.ReceiptFields memory receipt = _decodeSuccessfulReceipt(inclusion.encodedTransaction);
        if (receiptLogOrdinal >= receipt.receiptLogs.length) {
            revert ReceiptLogOrdinalOutOfBounds(receiptLogOrdinal, receipt.receiptLogs.length);
        }
        if (receiptLogOrdinal > type(uint64).max) revert ReceiptLogOrdinalDoesNotFit(receiptLogOrdinal);

        EvmV1Decoder.LogEntry memory logEntry = receipt.receiptLogs[receiptLogOrdinal];
        if (logEntry.address_ != AAVE_V3_POOL) revert WrongEmitter(AAVE_V3_POOL, logEntry.address_);

        bytes32 eventSignature = logEntry.topics.length == 0 ? bytes32(0) : logEntry.topics[0];
        FactKind kind;
        AaveFact memory fact;
        if (eventSignature == AAVE_BORROW) {
            kind = FactKind.BORROW;
            fact = _decodeBorrow(logEntry);
        } else if (eventSignature == AAVE_REPAY) {
            kind = FactKind.REPAY;
            fact = _decodeRepay(logEntry);
        } else {
            revert UnsupportedAaveEvent(eventSignature);
        }

        factId = keccak256(abi.encode("AAVE_USDC_FACT_V1", verified.evidenceId, receiptLogOrdinal, eventSignature));
        if (_facts[factId].kind != FactKind.NONE) revert FactAlreadyRecorded(factId);

        fact.kind = kind;
        // Bound checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        fact.receiptLogOrdinal = uint64(receiptLogOrdinal);
        fact.position = verified.position;
        fact.transactionEvidenceId = verified.evidenceId;
        _facts[factId] = fact;

        PerformanceBureau.EvidenceKind evidenceKind = kind == FactKind.BORROW
            ? PerformanceBureau.EvidenceKind.AaveBorrow
            : PerformanceBureau.EvidenceKind.AaveRepay;
        PERFORMANCE_BUREAU.recordEvidence(fact.subject, factId, evidenceKind, fact.amount, false);

        emit AaveFactRecorded(
            factId,
            verified.evidenceId,
            kind,
            fact.subject,
            fact.actor,
            fact.reserve,
            fact.amount,
            fact.position.blockHeight,
            fact.position.txIndex,
            fact.receiptLogOrdinal
        );
    }

    /// @notice Links two already verified facts into a positive, self-funded repayment observation.
    /// @dev Permissionless linking cannot change either authenticated fact and each fact may be used
    ///      in at most one observation. `matchedAmount` is the referenced Borrow amount, not a
    ///      statement about the subject's complete Aave balance.
    function linkVerifiedSelfRepayment(bytes32 borrowFactId, bytes32 repayFactId)
        external
        returns (bytes32 observationId)
    {
        AaveFact memory borrowFact = _requireFact(borrowFactId, FactKind.BORROW);
        AaveFact memory repayFact = _requireFact(repayFactId, FactKind.REPAY);

        if (borrowFact.subject != repayFact.subject) {
            revert SubjectMismatch(borrowFact.subject, repayFact.subject);
        }
        if (borrowFact.reserve != repayFact.reserve) {
            revert ReserveMismatch(borrowFact.reserve, repayFact.reserve);
        }
        if (repayFact.actor != repayFact.subject) {
            revert RepaymentNotSelfFunded(repayFact.subject, repayFact.actor);
        }
        if (!OrderingPredicates.isBefore(borrowFact.position, repayFact.position)) {
            revert RepaymentNotAfterBorrow(borrowFact.position.blockHeight, repayFact.position.blockHeight);
        }

        uint64 sourceBlockGap = repayFact.position.blockHeight - borrowFact.position.blockHeight;
        if (sourceBlockGap < MINIMUM_SELF_REPAYMENT_BLOCK_GAP) {
            revert SourceBlockGapTooSmall(MINIMUM_SELF_REPAYMENT_BLOCK_GAP, sourceBlockGap);
        }
        if (repayFact.amount < borrowFact.amount) {
            revert RepaymentAmountTooSmall(borrowFact.amount, repayFact.amount);
        }
        if (factUsedInObservation[borrowFactId]) revert FactAlreadyUsed(borrowFactId);
        if (factUsedInObservation[repayFactId]) revert FactAlreadyUsed(repayFactId);

        observationId = keccak256(abi.encode("AAVE_VERIFIED_SELF_REPAYMENT_V1", borrowFactId, repayFactId));
        factUsedInObservation[borrowFactId] = true;
        factUsedInObservation[repayFactId] = true;
        _observations[observationId] = SelfRepaymentObservation({
            subject: borrowFact.subject,
            borrowFactId: borrowFactId,
            repayFactId: repayFactId,
            matchedAmount: borrowFact.amount,
            sourceBlockGap: sourceBlockGap
        });

        PERFORMANCE_BUREAU.recordEvidence(
            borrowFact.subject,
            observationId,
            PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation,
            borrowFact.amount,
            false
        );
        emit VerifiedSelfRepaymentLinked(
            observationId, borrowFactId, repayFactId, borrowFact.subject, borrowFact.amount, sourceBlockGap
        );
    }

    function _decodeSuccessfulReceipt(bytes memory encodedTransaction)
        private
        pure
        returns (EvmV1Decoder.ReceiptFields memory receipt)
    {
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTransactionType(txType);
        receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) revert SourceTransactionReverted(receipt.receiptStatus);
    }

    function _decodeBorrow(EvmV1Decoder.LogEntry memory logEntry) private pure returns (AaveFact memory fact) {
        _assertEventShape(logEntry, AAVE_BORROW, BORROW_DATA_LENGTH);
        address reserve = _indexedAddress(logEntry.topics[1]);
        address subject = _indexedAddress(logEntry.topics[2]);
        if (uint256(logEntry.topics[3]) > type(uint16).max) {
            revert MalformedEvent(AAVE_BORROW, logEntry.topics.length, logEntry.data.length);
        }
        if (reserve != USDC) revert UnsupportedReserve(reserve);
        if (subject == address(0)) revert InvalidSubject();

        (address user, uint256 amount, uint8 interestRateMode,) =
            abi.decode(logEntry.data, (address, uint256, uint8, uint256));
        if (interestRateMode != 1 && interestRateMode != 2) {
            revert UnsupportedInterestRateMode(interestRateMode);
        }
        fact.subject = subject;
        fact.actor = user;
        fact.reserve = reserve;
        fact.amount = _toUint128(amount);
        fact.interestRateMode = interestRateMode;
    }

    function _decodeRepay(EvmV1Decoder.LogEntry memory logEntry) private pure returns (AaveFact memory fact) {
        _assertEventShape(logEntry, AAVE_REPAY, REPAY_DATA_LENGTH);
        address reserve = _indexedAddress(logEntry.topics[1]);
        address subject = _indexedAddress(logEntry.topics[2]);
        address repayer = _indexedAddress(logEntry.topics[3]);
        if (reserve != USDC) revert UnsupportedReserve(reserve);
        if (subject == address(0)) revert InvalidSubject();

        (uint256 amount, bool useATokens) = abi.decode(logEntry.data, (uint256, bool));
        fact.subject = subject;
        fact.actor = repayer;
        fact.reserve = reserve;
        fact.amount = _toUint128(amount);
        fact.useATokens = useATokens;
    }

    function _assertEventShape(EvmV1Decoder.LogEntry memory logEntry, bytes32 signature, uint256 dataLength)
        private
        pure
    {
        if (logEntry.topics.length != AAVE_EVENT_TOPICS || logEntry.data.length != dataLength) {
            revert MalformedEvent(signature, logEntry.topics.length, logEntry.data.length);
        }
    }

    function _indexedAddress(bytes32 topic) private pure returns (address decoded) {
        uint256 raw = uint256(topic);
        if (raw >> 160 != 0) revert MalformedIndexedAddress(topic);
        // The upper 96 bits were checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        decoded = address(uint160(raw));
    }

    function _toUint128(uint256 amount) private pure returns (uint128) {
        if (amount > type(uint128).max) revert AmountDoesNotFit(amount);
        // Bound checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(amount);
    }

    function _requireFact(bytes32 factId, FactKind expected) private view returns (AaveFact memory fact) {
        fact = _facts[factId];
        if (fact.kind == FactKind.NONE) revert FactNotFound(factId);
        if (fact.kind != expected) revert WrongFactKind(factId, expected, fact.kind);
    }
}
