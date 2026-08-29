// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PromiseBook } from "./PromiseBook.sol";
import { AttestcoinProofAdapter } from "./attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "./attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";

/// @title PromiseCourt
/// @notice Resolves bonded RFQ-execution and settlement promises from one exact,
///         Attestcoin-authenticated source receipt event.
/// @dev Relevance fields are strict gates: a proof for a different promise, reference, actor,
///      chain, emitter, kind or terms commitment reverts. Once relevance is established, the
///      court deterministically classifies the selected event as fulfilled or breached. A late
///      event is positive breach evidence; absence is handled separately by PromiseBook's
///      proof-submission default and is not inferred here. The committed source contract must
///      enforce at most one final event per `(promise ID, actor)` across transactions. The court
///      rejects same-receipt ambiguity but cannot derive that source invariant itself.
contract PromiseCourt is AttestcoinProofAdapter {
    bytes32 public constant RFQ_EXECUTED =
        keccak256("RFQExecuted(bytes32,bytes32,address,address,address,address,uint256,uint256,address)");
    bytes32 public constant SETTLEMENT_RELEASED =
        keccak256("SettlementReleased(bytes32,bytes32,address,address,address,uint256)");

    uint256 public constant REASON_LATE = 1;
    uint256 public constant REASON_WRONG_BENEFICIARY = 1 << 1;
    uint256 public constant REASON_WRONG_INPUT_ASSET = 1 << 2;
    uint256 public constant REASON_WRONG_OUTPUT_ASSET = 1 << 3;
    uint256 public constant REASON_WRONG_INPUT_AMOUNT = 1 << 4;
    uint256 public constant REASON_SHORT_OUTPUT = 1 << 5;
    uint256 public constant REASON_WRONG_SETTLEMENT_ASSET = 1 << 6;
    uint256 public constant REASON_WRONG_RECIPIENT = 1 << 7;
    uint256 public constant REASON_SHORT_SETTLEMENT = 1 << 8;

    uint256 private constant EXPECTED_EVENT_TOPICS = 4;
    uint256 private constant RFQ_EVENT_DATA_LENGTH = 192;
    uint256 private constant SETTLEMENT_EVENT_DATA_LENGTH = 96;

    struct RfqTerms {
        bytes32 quoteId;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        address recipient;
    }

    struct SettlementTerms {
        bytes32 settlementId;
        address asset;
        uint256 minAmount;
        address recipient;
    }

    struct RfqExecution {
        address beneficiary;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        address recipient;
    }

    struct SettlementRelease {
        address asset;
        address recipient;
        uint256 amount;
    }

    struct Verdict {
        bytes32 evidenceId;
        PromiseBook.Outcome outcome;
        uint64 evidenceHeight;
        uint64 sourceTxIndex;
        uint64 receiptLogOrdinal;
        uint256 reasonBits;
    }

    PromiseBook public immutable PROMISE_BOOK;

    mapping(bytes32 promiseId => Verdict verdict) private _verdicts;
    uint256 private _entered;

    event PromiseOutcomeProven(
        bytes32 indexed promiseId,
        bytes32 indexed evidenceId,
        PromiseBook.PromiseKind indexed kind,
        PromiseBook.Outcome outcome,
        uint64 evidenceHeight,
        uint64 sourceTxIndex,
        uint64 receiptLogOrdinal,
        uint256 reasonBits
    );

    error ZeroAddress();
    error PromiseNotFound(bytes32 promiseId);
    error PromiseAlreadyResolved(bytes32 promiseId, PromiseBook.Outcome outcome);
    error WrongPromiseKind(PromiseBook.PromiseKind expected, PromiseBook.PromiseKind actual);
    error WrongSourceChain(uint64 expected, uint64 actual);
    error ZeroReferenceId();
    error ZeroTermsAddress();
    error ZeroTermsAmount();
    error IdenticalRfqAssets(address asset);
    error TermsHashMismatch(bytes32 committed, bytes32 supplied);
    error UnsupportedTransactionType(uint8 txType);
    error SourceTransactionReverted(uint8 receiptStatus);
    error ReceiptLogOrdinalOutOfBounds(uint256 ordinal, uint256 logCount);
    error ReceiptLogOrdinalDoesNotFit(uint256 ordinal);
    error WrongEmitter(address expected, address actual);
    error WrongEventSignature(bytes32 expected, bytes32 actual);
    error MalformedEvent(bytes32 eventSignature, uint256 topicCount, uint256 dataLength);
    error EmbeddedPromiseIdMismatch(bytes32 expected, bytes32 actual);
    error ReferenceIdMismatch(bytes32 expected, bytes32 actual);
    error ActorMismatch(address expected, address actual);
    error MalformedIndexedAddress(bytes32 topic);
    error AmbiguousTerminalEvents(bytes32 promiseId, bytes32 eventSignature, uint256 count);
    error Reentrancy();

    constructor(INativeQueryVerifier verifier_, PromiseBook promiseBook_) AttestcoinProofAdapter(verifier_) {
        if (address(promiseBook_) == address(0)) revert ZeroAddress();
        PROMISE_BOOK = promiseBook_;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_entered != 0) revert Reentrancy();
        _entered = 1;
    }

    function _nonReentrantAfter() private {
        _entered = 0;
    }

    function verdictOf(bytes32 promiseId) external view returns (Verdict memory) {
        return _verdicts[promiseId];
    }

    /// @notice Commitment interpreted for an RFQ_EXECUTION promise.
    /// @dev The event signature and unique-final-event source invariant are part of the policy.
    function rfqTermsHash(RfqTerms memory terms) public pure returns (bytes32) {
        _validateRfqTerms(terms);
        return keccak256(
            abi.encode(
                "PROMISE_COURT_RFQ_TERMS_V3",
                RFQ_EXECUTED,
                "UNIQUE_FINAL_EVENT_PER_PROMISE_ID_AND_ACTOR",
                terms.quoteId,
                terms.inputToken,
                terms.outputToken,
                terms.inputAmount,
                terms.minOutputAmount,
                terms.recipient
            )
        );
    }

    /// @notice Commitment interpreted for a SETTLEMENT promise.
    /// @dev The event signature and unique-final-event source invariant are part of the policy.
    function settlementTermsHash(SettlementTerms memory terms) public pure returns (bytes32) {
        _validateSettlementTerms(terms);
        return keccak256(
            abi.encode(
                "PROMISE_COURT_SETTLEMENT_TERMS_V3",
                SETTLEMENT_RELEASED,
                "UNIQUE_FINAL_EVENT_PER_PROMISE_ID_AND_ACTOR",
                terms.settlementId,
                terms.asset,
                terms.minAmount,
                terms.recipient
            )
        );
    }

    /// @notice Authenticates one exact RFQExecuted receipt log and resolves the referenced promise.
    function proveRfqOutcome(
        bytes32 promiseId,
        RfqTerms calldata terms,
        BlockContext calldata context,
        TransactionInclusion calldata inclusion,
        uint256 receiptLogOrdinal
    ) external nonReentrant returns (bytes32 evidenceId, PromiseBook.Outcome outcome, uint256 reasonBits) {
        PromiseBook.PromiseRecord memory record =
            _loadPromise(promiseId, PromiseBook.PromiseKind.RFQ_EXECUTION, context.chainKey, rfqTermsHash(terms));

        (VerifiedTransaction memory verified, EvmV1Decoder.LogEntry memory logEntry) = _authenticateEvent(
            promiseId, terms.quoteId, record, context, inclusion, receiptLogOrdinal, RFQ_EXECUTED, RFQ_EVENT_DATA_LENGTH
        );
        RfqExecution memory execution = _decodeRfq(logEntry);
        reasonBits = _rfqReasonBits(record, terms, execution, context.blockHeight);
        outcome = _outcome(reasonBits);
        evidenceId = _eventEvidenceId(promiseId, verified.evidenceId, receiptLogOrdinal, RFQ_EXECUTED);
        _resolve(
            promiseId,
            evidenceId,
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            outcome,
            reasonBits,
            receiptLogOrdinal,
            verified
        );
    }

    /// @notice Authenticates one exact SettlementReleased receipt log and resolves the promise.
    function proveSettlementOutcome(
        bytes32 promiseId,
        SettlementTerms calldata terms,
        BlockContext calldata context,
        TransactionInclusion calldata inclusion,
        uint256 receiptLogOrdinal
    ) external nonReentrant returns (bytes32 evidenceId, PromiseBook.Outcome outcome, uint256 reasonBits) {
        PromiseBook.PromiseRecord memory record =
            _loadPromise(promiseId, PromiseBook.PromiseKind.SETTLEMENT, context.chainKey, settlementTermsHash(terms));

        (VerifiedTransaction memory verified, EvmV1Decoder.LogEntry memory logEntry) = _authenticateEvent(
            promiseId,
            terms.settlementId,
            record,
            context,
            inclusion,
            receiptLogOrdinal,
            SETTLEMENT_RELEASED,
            SETTLEMENT_EVENT_DATA_LENGTH
        );
        SettlementRelease memory release = _decodeSettlement(logEntry);
        reasonBits = _settlementReasonBits(record, terms, release, context.blockHeight);
        outcome = _outcome(reasonBits);
        evidenceId = _eventEvidenceId(promiseId, verified.evidenceId, receiptLogOrdinal, SETTLEMENT_RELEASED);
        _resolve(
            promiseId, evidenceId, PromiseBook.PromiseKind.SETTLEMENT, outcome, reasonBits, receiptLogOrdinal, verified
        );
    }

    function _loadPromise(
        bytes32 promiseId,
        PromiseBook.PromiseKind expectedKind,
        uint64 sourceChainKey,
        bytes32 suppliedTermsHash
    ) private view returns (PromiseBook.PromiseRecord memory record) {
        record = PROMISE_BOOK.promiseOf(promiseId);
        if (record.terms.actor == address(0)) revert PromiseNotFound(promiseId);
        if (record.outcome != PromiseBook.Outcome.OPEN) revert PromiseAlreadyResolved(promiseId, record.outcome);
        if (record.terms.kind != expectedKind) revert WrongPromiseKind(expectedKind, record.terms.kind);
        if (sourceChainKey != record.terms.sourceChainKey) {
            revert WrongSourceChain(record.terms.sourceChainKey, sourceChainKey);
        }
        if (suppliedTermsHash != record.terms.termsHash) {
            revert TermsHashMismatch(record.terms.termsHash, suppliedTermsHash);
        }
    }

    function _authenticateEvent(
        bytes32 promiseId,
        bytes32 referenceId,
        PromiseBook.PromiseRecord memory record,
        BlockContext calldata context,
        TransactionInclusion calldata inclusion,
        uint256 receiptLogOrdinal,
        bytes32 eventSignature,
        uint256 expectedDataLength
    ) private returns (VerifiedTransaction memory verified, EvmV1Decoder.LogEntry memory logEntry) {
        verified = _verifyTransaction(context, inclusion, 0);
        EvmV1Decoder.ReceiptFields memory receipt = _decodeSuccessfulReceipt(inclusion.encodedTransaction);
        if (receiptLogOrdinal > type(uint64).max) revert ReceiptLogOrdinalDoesNotFit(receiptLogOrdinal);
        if (receiptLogOrdinal >= receipt.receiptLogs.length) {
            revert ReceiptLogOrdinalOutOfBounds(receiptLogOrdinal, receipt.receiptLogs.length);
        }

        logEntry = receipt.receiptLogs[receiptLogOrdinal];
        if (logEntry.address_ != record.terms.sourceContract) {
            revert WrongEmitter(record.terms.sourceContract, logEntry.address_);
        }
        bytes32 actualSignature = logEntry.topics.length == 0 ? bytes32(0) : logEntry.topics[0];
        if (actualSignature != eventSignature) revert WrongEventSignature(eventSignature, actualSignature);
        if (logEntry.topics.length != EXPECTED_EVENT_TOPICS || logEntry.data.length != expectedDataLength) {
            revert MalformedEvent(eventSignature, logEntry.topics.length, logEntry.data.length);
        }
        if (logEntry.topics[1] != promiseId) revert EmbeddedPromiseIdMismatch(promiseId, logEntry.topics[1]);
        if (logEntry.topics[2] != referenceId) revert ReferenceIdMismatch(referenceId, logEntry.topics[2]);

        address actor = _indexedAddress(logEntry.topics[3]);
        if (actor != record.terms.actor) revert ActorMismatch(record.terms.actor, actor);
        _rejectAmbiguousTerminalEvents(receipt, record.terms.sourceContract, promiseId, actor, eventSignature);
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

    function _decodeRfq(EvmV1Decoder.LogEntry memory logEntry) private pure returns (RfqExecution memory execution) {
        (
            execution.beneficiary,
            execution.inputToken,
            execution.outputToken,
            execution.inputAmount,
            execution.outputAmount,
            execution.recipient
        ) = abi.decode(logEntry.data, (address, address, address, uint256, uint256, address));
    }

    function _decodeSettlement(EvmV1Decoder.LogEntry memory logEntry)
        private
        pure
        returns (SettlementRelease memory release)
    {
        (release.asset, release.recipient, release.amount) = abi.decode(logEntry.data, (address, address, uint256));
    }

    function _rfqReasonBits(
        PromiseBook.PromiseRecord memory record,
        RfqTerms calldata terms,
        RfqExecution memory execution,
        uint64 evidenceHeight
    ) private pure returns (uint256 reasons) {
        if (evidenceHeight > record.terms.fulfillmentDeadlineHeight) reasons |= REASON_LATE;
        if (execution.beneficiary != record.terms.beneficiary) reasons |= REASON_WRONG_BENEFICIARY;
        if (execution.inputToken != terms.inputToken) reasons |= REASON_WRONG_INPUT_ASSET;
        if (execution.outputToken != terms.outputToken) reasons |= REASON_WRONG_OUTPUT_ASSET;
        if (execution.inputAmount != terms.inputAmount) reasons |= REASON_WRONG_INPUT_AMOUNT;
        if (execution.outputAmount < terms.minOutputAmount) reasons |= REASON_SHORT_OUTPUT;
        if (execution.recipient != terms.recipient) reasons |= REASON_WRONG_RECIPIENT;
    }

    function _settlementReasonBits(
        PromiseBook.PromiseRecord memory record,
        SettlementTerms calldata terms,
        SettlementRelease memory release,
        uint64 evidenceHeight
    ) private pure returns (uint256 reasons) {
        if (evidenceHeight > record.terms.fulfillmentDeadlineHeight) reasons |= REASON_LATE;
        if (release.asset != terms.asset) reasons |= REASON_WRONG_SETTLEMENT_ASSET;
        if (release.recipient != terms.recipient) reasons |= REASON_WRONG_RECIPIENT;
        if (release.amount < terms.minAmount) reasons |= REASON_SHORT_SETTLEMENT;
    }

    function _resolve(
        bytes32 promiseId,
        bytes32 evidenceId,
        PromiseBook.PromiseKind kind,
        PromiseBook.Outcome outcome,
        uint256 reasonBits,
        uint256 receiptLogOrdinal,
        VerifiedTransaction memory verified
    ) private {
        // Bound checked in _authenticateEvent.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 ordinal = uint64(receiptLogOrdinal);
        Verdict memory verdict = Verdict({
            evidenceId: evidenceId,
            outcome: outcome,
            evidenceHeight: verified.position.blockHeight,
            sourceTxIndex: verified.position.txIndex,
            receiptLogOrdinal: ordinal,
            reasonBits: reasonBits
        });
        _verdicts[promiseId] = verdict;
        PROMISE_BOOK.resolveWithEvidence(promiseId, evidenceId, verdict.evidenceHeight, outcome);

        emit PromiseOutcomeProven(
            promiseId, evidenceId, kind, outcome, verdict.evidenceHeight, verdict.sourceTxIndex, ordinal, reasonBits
        );
    }

    function _outcome(uint256 reasonBits) private pure returns (PromiseBook.Outcome) {
        return reasonBits == 0 ? PromiseBook.Outcome.FULFILLED : PromiseBook.Outcome.BREACHED;
    }

    function _eventEvidenceId(
        bytes32 promiseId,
        bytes32 transactionEvidenceId,
        uint256 receiptLogOrdinal,
        bytes32 eventSignature
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "PROMISE_COURT_SOURCE_EVENT_V2", promiseId, transactionEvidenceId, receiptLogOrdinal, eventSignature
            )
        );
    }

    /// @dev Promise terms bind the source emitter to unique-final-event semantics. This local
    ///      scan rejects contradictions within the authenticated receipt. Cross-transaction
    ///      uniqueness necessarily relies on the committed source contract enforcing that policy.
    function _rejectAmbiguousTerminalEvents(
        EvmV1Decoder.ReceiptFields memory receipt,
        address sourceContract,
        bytes32 promiseId,
        address actor,
        bytes32 eventSignature
    ) private pure {
        bytes32 actorTopic = bytes32(uint256(uint160(actor)));
        uint256 count;
        for (uint256 i; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory candidate = receipt.receiptLogs[i];
            if (
                candidate.address_ == sourceContract && candidate.topics.length >= EXPECTED_EVENT_TOPICS
                    && candidate.topics[0] == eventSignature && candidate.topics[1] == promiseId
                    && candidate.topics[3] == actorTopic
            ) {
                ++count;
            }
        }
        if (count != 1) revert AmbiguousTerminalEvents(promiseId, eventSignature, count);
    }

    function _validateRfqTerms(RfqTerms memory terms) private pure {
        if (terms.quoteId == bytes32(0)) revert ZeroReferenceId();
        if (terms.inputToken == address(0) || terms.outputToken == address(0) || terms.recipient == address(0)) {
            revert ZeroTermsAddress();
        }
        if (terms.inputAmount == 0 || terms.minOutputAmount == 0) revert ZeroTermsAmount();
        if (terms.inputToken == terms.outputToken) revert IdenticalRfqAssets(terms.inputToken);
    }

    function _validateSettlementTerms(SettlementTerms memory terms) private pure {
        if (terms.settlementId == bytes32(0)) revert ZeroReferenceId();
        if (terms.asset == address(0) || terms.recipient == address(0)) revert ZeroTermsAddress();
        if (terms.minAmount == 0) revert ZeroTermsAmount();
    }

    function _indexedAddress(bytes32 topic) private pure returns (address decoded) {
        uint256 raw = uint256(topic);
        if (raw >> 160 != 0) revert MalformedIndexedAddress(topic);
        // Upper 96 bits checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        decoded = address(uint160(raw));
    }
}
