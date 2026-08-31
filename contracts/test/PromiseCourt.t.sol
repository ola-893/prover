// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { DemoPromiseSource } from "../src/DemoPromiseSource.sol";
import { NativePromiseCourtDeployer } from "../src/NativePromiseCourtDeployer.sol";
import { IPromiseAttestedHeightSource, PromiseBook } from "../src/PromiseBook.sol";
import { PromiseCourt } from "../src/PromiseCourt.sol";
import { PromiseCourtDeployer } from "../src/PromiseCourtDeployer.sol";
import { PromiseSourceRegistry } from "../src/PromiseSourceRegistry.sol";
import { AttestcoinProofAdapter } from "../src/attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "../src/attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "../src/attestcoin/INativeQueryVerifier.sol";
import { EvmV1Fixture } from "./helpers/EvmV1Fixture.sol";
import { MockNativeQueryVerifier } from "./mocks/MockNativeQueryVerifier.sol";
import { TestBase, Vm } from "./TestBase.sol";

contract PromiseCourtHeightSource is IPromiseAttestedHeightSource {
    mapping(uint64 chainKey => HeightHashResult result) private _tips;

    function setTip(uint64 chainKey, uint64 height, bool isAttestation, bool exists) external {
        _tips[chainKey] = HeightHashResult({
            height: height,
            hash: keccak256(abi.encode("promise-court-tip", chainKey, height)),
            isAttestation: isAttestation,
            exists: exists
        });
    }

    // Exact native ChainInfo ABI.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_latest_attestation_height_and_hash(uint64 chainKey)
        external
        view
        returns (HeightHashResult memory result)
    {
        return _tips[chainKey];
    }
}

contract PromiseCourtTest is TestBase {
    uint64 private constant CHAIN_KEY = 3;
    uint64 private constant INITIAL_TIP = 1_000;
    uint64 private constant VALID_FROM = 1_100;
    uint64 private constant FULFILLMENT_DEADLINE = 1_200;
    uint64 private constant PROOF_DEADLINE = 1_300;

    address private constant ACTOR = address(0xA11CE);
    uint256 private constant BENEFICIARY_KEY = 0xB0B;
    address private constant RECIPIENT = address(0xCAFE);
    address private constant OTHER = address(0xBAD);
    address private constant INPUT_TOKEN = address(0x1111);
    address private constant OUTPUT_TOKEN = address(0x2222);
    address private constant SETTLEMENT_ASSET = address(0x3333);

    bytes32 private constant QUOTE_ID = keccak256("quote-17");
    bytes32 private constant SETTLEMENT_ID = keccak256("settlement-42");
    uint256 private constant INPUT_AMOUNT = 100 ether;
    uint256 private constant MIN_OUTPUT_AMOUNT = 99 ether;
    uint256 private constant MIN_SETTLEMENT_AMOUNT = 25 ether;
    uint256 private constant BOND = 12 ether;
    uint256 private constant PENALTY = 10 ether;
    bytes32 private constant ENTROPY_HASH = keccak256("promise-court-anchor");

    MockNativeQueryVerifier private verifier;
    PromiseCourtHeightSource private chainInfo;
    PromiseCourtDeployer private system;
    PromiseBook private book;
    PromiseCourt private court;
    DemoPromiseSource private source;
    address private beneficiary;
    uint256 private authorizationNonce;

    function setUp() public {
        beneficiary = vm.addr(BENEFICIARY_KEY);
        verifier = new MockNativeQueryVerifier();
        chainInfo = new PromiseCourtHeightSource();
        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true, true);
        system = new PromiseCourtDeployer(verifier, chainInfo, address(this));
        book = system.PROMISE_BOOK();
        court = system.PROMISE_COURT();
        source = new DemoPromiseSource();
        PromiseSourceRegistry registry = system.SOURCE_REGISTRY();
        registry.setSourceApproval(
            uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, address(source), court.RFQ_POLICY_ID(), true
        );
        registry.setSourceApproval(
            uint8(PromiseBook.PromiseKind.SETTLEMENT), CHAIN_KEY, address(source), court.SETTLEMENT_POLICY_ID(), true
        );
        vm.deal(ACTOR, 1_000 ether);
    }

    function test_ReasonBitsAndEventSchemasAreStable() public view {
        assertEq(court.REASON_LATE(), 1);
        assertEq(court.REASON_WRONG_BENEFICIARY(), 2);
        assertEq(court.REASON_WRONG_INPUT_ASSET(), 4);
        assertEq(court.REASON_WRONG_OUTPUT_ASSET(), 8);
        assertEq(court.REASON_WRONG_INPUT_AMOUNT(), 16);
        assertEq(court.REASON_SHORT_OUTPUT(), 32);
        assertEq(court.REASON_WRONG_SETTLEMENT_ASSET(), 64);
        assertEq(court.REASON_WRONG_RECIPIENT(), 128);
        assertEq(court.REASON_SHORT_SETTLEMENT(), 256);
        assertEq(
            court.RFQ_EXECUTED(),
            keccak256("RFQExecuted(bytes32,bytes32,address,address,address,address,uint256,uint256,address)")
        );
        assertEq(
            court.SETTLEMENT_RELEASED(),
            keccak256("SettlementReleased(bytes32,bytes32,address,address,address,uint256)")
        );
        assertEq(court.RFQ_POLICY_ID(), keccak256("PROVER_PROMISE_RFQ_EXECUTED_V1"));
        assertEq(court.SETTLEMENT_POLICY_ID(), keccak256("PROVER_PROMISE_SETTLEMENT_RELEASED_V1"));
    }

    function test_InjectableDeployerPermanentlyWiresBookAndCourt() public view {
        assertEq(address(book.CHAIN_INFO()), address(chainInfo));
        assertEq(address(court.VERIFIER()), address(verifier));
        assertEq(address(court.PROMISE_BOOK()), address(book));
        assertEq(address(book.SOURCE_REGISTRY()), address(system.SOURCE_REGISTRY()));
        assertEq(book.court(), address(court));
        assertEq(book.DEPLOYER(), address(system));
    }

    function test_NativeDeployerPinsCreditcoinPrecompiles() public {
        NativePromiseCourtDeployer nativeSystem = new NativePromiseCourtDeployer(address(this));
        PromiseBook nativeBook = nativeSystem.PROMISE_BOOK();
        PromiseCourt nativeCourt = nativeSystem.PROMISE_COURT();

        assertEq(address(nativeCourt.VERIFIER()), nativeSystem.NATIVE_QUERY_VERIFIER());
        assertEq(address(nativeBook.CHAIN_INFO()), nativeSystem.NATIVE_CHAIN_INFO());
        assertEq(address(nativeCourt.PROMISE_BOOK()), address(nativeBook));
        assertEq(nativeSystem.SOURCE_REGISTRY().governor(), address(this));
        assertEq(nativeBook.court(), address(nativeCourt));
    }

    function test_RfqTermsCommitEveryPolicyField() public view {
        PromiseCourt.RfqTerms memory base = _rfqTerms();
        bytes32 expected = keccak256(
            abi.encode(
                "PROMISE_COURT_RFQ_TERMS_V4",
                court.RFQ_POLICY_ID(),
                court.RFQ_EXECUTED(),
                "UNIQUE_FINAL_EVENT_PER_PROMISE_ID_AND_ACTOR",
                QUOTE_ID,
                INPUT_TOKEN,
                OUTPUT_TOKEN,
                INPUT_AMOUNT,
                MIN_OUTPUT_AMOUNT,
                RECIPIENT
            )
        );
        assertEq(court.rfqTermsHash(base), expected);

        PromiseCourt.RfqTerms memory changed = _rfqTerms();
        changed.recipient = OTHER;
        assertTrue(court.rfqTermsHash(changed) != expected);
        changed = _rfqTerms();
        changed.minOutputAmount = MIN_OUTPUT_AMOUNT + 1;
        assertTrue(court.rfqTermsHash(changed) != expected);
    }

    function test_SettlementTermsCommitEveryPolicyField() public view {
        PromiseCourt.SettlementTerms memory terms = _settlementTerms();
        bytes32 expected = keccak256(
            abi.encode(
                "PROMISE_COURT_SETTLEMENT_TERMS_V4",
                court.SETTLEMENT_POLICY_ID(),
                court.SETTLEMENT_RELEASED(),
                "UNIQUE_FINAL_EVENT_PER_PROMISE_ID_AND_ACTOR",
                SETTLEMENT_ID,
                SETTLEMENT_ASSET,
                MIN_SETTLEMENT_AMOUNT,
                RECIPIENT
            )
        );
        assertEq(court.settlementTermsHash(terms), expected);

        PromiseCourt.SettlementTerms memory changed = _settlementTerms();
        changed.recipient = OTHER;
        assertTrue(court.settlementTermsHash(changed) != expected);
    }

    function test_TermsRejectZeroIdsAddressesAmountsAndEqualRfqAssets() public {
        PromiseCourt.RfqTerms memory rfq = _rfqTerms();
        rfq.quoteId = bytes32(0);
        vm.expectRevert(PromiseCourt.ZeroReferenceId.selector);
        court.rfqTermsHash(rfq);

        rfq = _rfqTerms();
        rfq.inputToken = address(0);
        vm.expectRevert(PromiseCourt.ZeroTermsAddress.selector);
        court.rfqTermsHash(rfq);

        rfq = _rfqTerms();
        rfq.inputAmount = 0;
        vm.expectRevert(PromiseCourt.ZeroTermsAmount.selector);
        court.rfqTermsHash(rfq);

        rfq = _rfqTerms();
        rfq.outputToken = rfq.inputToken;
        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.IdenticalRfqAssets.selector, INPUT_TOKEN));
        court.rfqTermsHash(rfq);

        PromiseCourt.SettlementTerms memory settlement = _settlementTerms();
        settlement.asset = address(0);
        vm.expectRevert(PromiseCourt.ZeroTermsAddress.selector);
        court.settlementTermsHash(settlement);

        settlement = _settlementTerms();
        settlement.minAmount = 0;
        vm.expectRevert(PromiseCourt.ZeroTermsAmount.selector);
        court.settlementTermsHash(settlement);
    }

    function test_CorrectTimelyRfqIsFulfilledAndRefundsBond() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        PromiseCourt.RfqExecution memory execution = _validRfqExecution();

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, execution);
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(FULFILLMENT_DEADLINE, encoded, false);

        (bytes32 evidenceId, PromiseBook.Outcome outcome, uint256 reasons) =
            court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
        assertEq(uint256(outcome), uint256(PromiseBook.Outcome.FULFILLED));
        assertEq(reasons, 0);
        assertEq(book.claimable(ACTOR), BOND);
        assertEq(book.claimable(beneficiary), 0);

        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);
        PromiseCourt.Verdict memory verdict = court.verdictOf(promiseId);
        assertEq(uint256(record.outcome), uint256(PromiseBook.Outcome.FULFILLED));
        assertEq(record.evidenceId, evidenceId);
        assertEq(verdict.evidenceId, evidenceId);
        assertEq(uint256(verdict.outcome), uint256(PromiseBook.Outcome.FULFILLED));
        assertEq(verdict.evidenceHeight, FULFILLMENT_DEADLINE);
        assertEq(verdict.sourceTxIndex, 0);
        assertEq(verdict.receiptLogOrdinal, 0);
        assertEq(verdict.reasonBits, 0);

        bytes32 transactionEvidenceId = keccak256(
            abi.encode(CHAIN_KEY, FULFILLMENT_DEADLINE, uint64(0), keccak256(encoded), inclusion.merkleRoot)
        );
        assertEq(
            evidenceId,
            keccak256(
                abi.encode(
                    "PROMISE_COURT_SOURCE_EVENT_V2", promiseId, transactionEvidenceId, uint256(0), court.RFQ_EXECUTED()
                )
            )
        );
    }

    function test_AllRfqDefectsAndPositiveLatenessComposeIntoReasonBits() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        PromiseCourt.RfqExecution memory execution = PromiseCourt.RfqExecution({
            beneficiary: OTHER,
            inputToken: OTHER,
            outputToken: OTHER,
            inputAmount: INPUT_AMOUNT - 1,
            outputAmount: MIN_OUTPUT_AMOUNT - 1,
            recipient: OTHER
        });
        uint64 height = FULFILLMENT_DEADLINE + 1;

        (PromiseBook.Outcome outcome, uint256 reasons) = _proveRfq(promiseId, terms, execution, height);
        uint256 expected = court.REASON_LATE() | court.REASON_WRONG_BENEFICIARY() | court.REASON_WRONG_INPUT_ASSET()
            | court.REASON_WRONG_OUTPUT_ASSET() | court.REASON_WRONG_INPUT_AMOUNT() | court.REASON_SHORT_OUTPUT()
            | court.REASON_WRONG_RECIPIENT();
        assertEq(uint256(outcome), uint256(PromiseBook.Outcome.BREACHED));
        assertEq(reasons, expected);
        assertEq(court.verdictOf(promiseId).reasonBits, expected);
        assertEq(book.claimable(beneficiary), PENALTY);
        assertEq(book.claimable(ACTOR), BOND - PENALTY);
    }

    function test_CorrectButLateRfqIsPositiveBreachEvidence() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        (PromiseBook.Outcome outcome, uint256 reasons) =
            _proveRfq(promiseId, terms, _validRfqExecution(), FULFILLMENT_DEADLINE + 1);

        assertEq(uint256(outcome), uint256(PromiseBook.Outcome.BREACHED));
        assertEq(reasons, court.REASON_LATE());
    }

    function test_CorrectTimelySettlementIsFulfilled() public {
        PromiseCourt.SettlementTerms memory terms = _settlementTerms();
        bytes32 promiseId = _openSettlement(terms);
        PromiseCourt.SettlementRelease memory release = PromiseCourt.SettlementRelease({
            asset: SETTLEMENT_ASSET, recipient: RECIPIENT, amount: MIN_SETTLEMENT_AMOUNT
        });

        (PromiseBook.Outcome outcome, uint256 reasons) =
            _proveSettlement(promiseId, terms, release, FULFILLMENT_DEADLINE);
        assertEq(uint256(outcome), uint256(PromiseBook.Outcome.FULFILLED));
        assertEq(reasons, 0);
        assertEq(book.claimable(ACTOR), BOND);
    }

    function test_AllSettlementDefectsAndLatenessComposeIntoReasonBits() public {
        PromiseCourt.SettlementTerms memory terms = _settlementTerms();
        bytes32 promiseId = _openSettlement(terms);
        PromiseCourt.SettlementRelease memory release =
            PromiseCourt.SettlementRelease({ asset: OTHER, recipient: OTHER, amount: MIN_SETTLEMENT_AMOUNT - 1 });

        (PromiseBook.Outcome outcome, uint256 reasons) =
            _proveSettlement(promiseId, terms, release, FULFILLMENT_DEADLINE + 1);
        uint256 expected = court.REASON_LATE() | court.REASON_WRONG_SETTLEMENT_ASSET() | court.REASON_WRONG_RECIPIENT()
            | court.REASON_SHORT_SETTLEMENT();
        assertEq(uint256(outcome), uint256(PromiseBook.Outcome.BREACHED));
        assertEq(reasons, expected);
        assertEq(book.claimable(beneficiary), PENALTY);
    }

    function test_KindChainTermsAndZeroReferenceArePreVerificationRelevanceGates() public {
        PromiseCourt.RfqTerms memory rfq = _rfqTerms();
        PromiseCourt.SettlementTerms memory settlement = _settlementTerms();
        bytes32 settlementPromise = _openSettlement(settlement);
        AttestcoinProofAdapter.BlockContext memory emptyContext;
        AttestcoinProofAdapter.TransactionInclusion memory emptyInclusion;

        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseCourt.WrongPromiseKind.selector,
                PromiseBook.PromiseKind.RFQ_EXECUTION,
                PromiseBook.PromiseKind.SETTLEMENT
            )
        );
        court.proveRfqOutcome(settlementPromise, rfq, emptyContext, emptyInclusion, 0);

        bytes32 rfqPromise = _openRfq(rfq);
        emptyContext.chainKey = CHAIN_KEY + 1;
        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.WrongSourceChain.selector, CHAIN_KEY, CHAIN_KEY + 1));
        court.proveRfqOutcome(rfqPromise, rfq, emptyContext, emptyInclusion, 0);

        emptyContext.chainKey = CHAIN_KEY;
        PromiseCourt.RfqTerms memory changed = _rfqTerms();
        changed.minOutputAmount += 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseCourt.TermsHashMismatch.selector, court.rfqTermsHash(rfq), court.rfqTermsHash(changed)
            )
        );
        court.proveRfqOutcome(rfqPromise, changed, emptyContext, emptyInclusion, 0);

        PromiseCourt.RfqTerms memory zeroReference = _rfqTerms();
        zeroReference.quoteId = bytes32(0);
        vm.expectRevert(PromiseCourt.ZeroReferenceId.selector);
        court.proveRfqOutcome(rfqPromise, zeroReference, emptyContext, emptyInclusion, 0);
        assertEq(verifier.verificationCalls(), 0);
    }

    function test_CourtRejectsKindCorrectPromiseWithDifferentPolicy() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 otherPolicy = keccak256("PROVER_PROMISE_RFQ_EXECUTED_EXPERIMENTAL");
        system.SOURCE_REGISTRY()
            .setSourceApproval(
                uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, address(source), otherPolicy, true
            );
        bytes32 promiseId = _openPromise(PromiseBook.PromiseKind.RFQ_EXECUTION, otherPolicy, court.rfqTermsHash(terms));
        AttestcoinProofAdapter.BlockContext memory emptyContext;
        AttestcoinProofAdapter.TransactionInclusion memory emptyInclusion;

        vm.expectRevert(
            abi.encodeWithSelector(PromiseCourt.UnsupportedPolicy.selector, court.RFQ_POLICY_ID(), otherPolicy)
        );
        court.proveRfqOutcome(promiseId, terms, emptyContext, emptyInclusion, 0);
        assertEq(verifier.verificationCalls(), 0);
    }

    function test_EmbeddedPromiseReferenceAndActorArePostAuthenticationRelevanceGates() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        PromiseCourt.RfqExecution memory execution = _validRfqExecution();

        _expectRfqGate(
            promiseId,
            terms,
            _rfqLog(address(source), keccak256("wrong-promise"), terms.quoteId, ACTOR, execution),
            abi.encodeWithSelector(
                PromiseCourt.EmbeddedPromiseIdMismatch.selector, promiseId, keccak256("wrong-promise")
            )
        );
        _expectRfqGate(
            promiseId,
            terms,
            _rfqLog(address(source), promiseId, keccak256("wrong-reference"), ACTOR, execution),
            abi.encodeWithSelector(
                PromiseCourt.ReferenceIdMismatch.selector, terms.quoteId, keccak256("wrong-reference")
            )
        );
        _expectRfqGate(
            promiseId,
            terms,
            _rfqLog(address(source), promiseId, terms.quoteId, OTHER, execution),
            abi.encodeWithSelector(PromiseCourt.ActorMismatch.selector, ACTOR, OTHER)
        );
        // Reverting the court call also rolls back the mock verifier's call counter.
        assertEq(verifier.verificationCalls(), 0);
        assertEq(uint256(book.promiseOf(promiseId).outcome), uint256(PromiseBook.Outcome.OPEN));
    }

    function test_ExactEmitterSignatureAndSchemaAreRequired() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        PromiseCourt.RfqExecution memory execution = _validRfqExecution();

        _expectRfqGate(
            promiseId,
            terms,
            _rfqLog(OTHER, promiseId, terms.quoteId, ACTOR, execution),
            abi.encodeWithSelector(PromiseCourt.WrongEmitter.selector, address(source), OTHER)
        );

        EvmV1Decoder.LogEntryTuple memory wrongSignature =
            _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, execution);
        wrongSignature.topics[0] = keccak256("SomeOtherEvent()");
        _expectRfqGate(
            promiseId,
            terms,
            wrongSignature,
            abi.encodeWithSelector(
                PromiseCourt.WrongEventSignature.selector, court.RFQ_EXECUTED(), keccak256("SomeOtherEvent()")
            )
        );

        EvmV1Decoder.LogEntryTuple memory malformed =
            _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, execution);
        malformed.data = abi.encode(execution.beneficiary);
        _expectRfqGate(
            promiseId,
            terms,
            malformed,
            abi.encodeWithSelector(PromiseCourt.MalformedEvent.selector, court.RFQ_EXECUTED(), uint256(4), uint256(32))
        );
    }

    function test_MalformedIndexedActorIsRejected() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple memory logEntry =
            _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, _validRfqExecution());
        bytes32 malformed = bytes32((uint256(1) << 200) | uint256(uint160(ACTOR)));
        logEntry.topics[3] = malformed;

        _expectRfqGate(
            promiseId, terms, logEntry, abi.encodeWithSelector(PromiseCourt.MalformedIndexedAddress.selector, malformed)
        );
    }

    function test_ExactCallerSelectedOrdinalIsDecodedAndEvidenceIdsAreDistinct() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 firstPromise = _openRfq(terms);
        bytes32 secondPromise = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = _rfqLog(address(source), firstPromise, terms.quoteId, ACTOR, _validRfqExecution());
        logs[1] = _rfqLog(address(source), secondPromise, terms.quoteId, ACTOR, _validRfqExecution());
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, true);

        bytes32 firstEvidence;
        bytes32 secondEvidence;
        (firstEvidence,,) = court.proveRfqOutcome(firstPromise, terms, context, inclusion, 0);
        (secondEvidence,,) = court.proveRfqOutcome(secondPromise, terms, context, inclusion, 1);
        assertTrue(firstEvidence != secondEvidence);
        assertEq(court.verdictOf(firstPromise).sourceTxIndex, 1);
        assertEq(court.verdictOf(firstPromise).receiptLogOrdinal, 0);
        assertEq(court.verdictOf(secondPromise).receiptLogOrdinal, 1);
    }

    function test_SelectedOrdinalCannotSearchPastAnIrrelevantLog() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, OTHER, _validRfqExecution());
        logs[1] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, _validRfqExecution());
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, false);

        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.ActorMismatch.selector, ACTOR, OTHER));
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 1);
        assertEq(uint256(book.promiseOf(promiseId).outcome), uint256(PromiseBook.Outcome.FULFILLED));
    }

    function test_DuplicateTerminalEventsForOnePromiseInAReceiptAreAmbiguous() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, _validRfqExecution());
        PromiseCourt.RfqExecution memory contradictory = _validRfqExecution();
        contradictory.outputAmount = MIN_OUTPUT_AMOUNT - 1;
        logs[1] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, contradictory);
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseCourt.AmbiguousTerminalEvents.selector, promiseId, court.RFQ_EXECUTED(), uint256(2)
            )
        );
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
        assertEq(uint256(book.promiseOf(promiseId).outcome), uint256(PromiseBook.Outcome.OPEN));
    }

    function test_OrdinalBoundsUnsupportedTypeAndFailedReceiptAreRejected() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 promiseId = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, _validRfqExecution());

        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, false);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseCourt.ReceiptLogOrdinalOutOfBounds.selector, uint256(1), uint256(1))
        );
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 1);

        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.ReceiptLogOrdinalDoesNotFit.selector, type(uint256).max));
        court.proveRfqOutcome(promiseId, terms, context, inclusion, type(uint256).max);

        bytes memory unsupported = _encodedTransaction(ACTOR, address(source), 1, logs, 5);
        (context, inclusion) = _prepare(1_150, unsupported, false);
        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.UnsupportedTransactionType.selector, uint8(5)));
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);

        bytes memory failed = EvmV1Fixture.encodeType2(ACTOR, address(source), 0, logs);
        (context, inclusion) = _prepare(1_150, failed, false);
        vm.expectRevert(abi.encodeWithSelector(PromiseCourt.SourceTransactionReverted.selector, uint8(0)));
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
        assertEq(uint256(book.promiseOf(promiseId).outcome), uint256(PromiseBook.Outcome.OPEN));
    }

    function test_OneAuthenticatedEventCannotResolveTwoPromises() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 firstPromise = _openRfq(terms);
        bytes32 secondPromise = _openRfq(terms);
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _rfqLog(address(source), firstPromise, terms.quoteId, ACTOR, _validRfqExecution());
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, false);

        court.proveRfqOutcome(firstPromise, terms, context, inclusion, 0);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseCourt.EmbeddedPromiseIdMismatch.selector, secondPromise, firstPromise)
        );
        court.proveRfqOutcome(secondPromise, terms, context, inclusion, 0);
        assertEq(uint256(book.promiseOf(secondPromise).outcome), uint256(PromiseBook.Outcome.OPEN));
    }

    function test_BookEnforcesActivationAttestationAndProofDeadlineBoundaries() public {
        PromiseCourt.RfqTerms memory terms = _rfqTerms();
        bytes32 earlyPromise = _openRfq(terms);
        _expectBookWindowRevert(
            earlyPromise,
            terms,
            VALID_FROM - 1,
            abi.encodeWithSelector(PromiseBook.EvidenceBeforeActivation.selector, VALID_FROM - 1, VALID_FROM)
        );

        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true, true);
        bytes32 latePromise = _openRfq(terms);
        _expectBookWindowRevert(
            latePromise,
            terms,
            PROOF_DEADLINE + 1,
            abi.encodeWithSelector(
                PromiseBook.BreachEvidenceAfterProofDeadline.selector, PROOF_DEADLINE + 1, PROOF_DEADLINE
            )
        );
    }

    function test_DemoSourceAttributesActorAndPermitsOnlyOneEventPerReference() public {
        bytes32 sharedPromiseId = keccak256("front-run-target-promise");
        bytes32 sharedReferenceId = keccak256("front-run-target-reference");
        vm.prank(OTHER);
        source.releaseSettlement(sharedPromiseId, sharedReferenceId, SETTLEMENT_ASSET, RECIPIENT, 1 ether);
        vm.prank(ACTOR);
        source.releaseSettlement(sharedPromiseId, sharedReferenceId, SETTLEMENT_ASSET, RECIPIENT, 1 ether);
        assertTrue(source.promiseEmitted(OTHER, sharedPromiseId));
        assertTrue(source.promiseEmitted(ACTOR, sharedPromiseId));
        assertTrue(source.referenceEmitted(OTHER, sharedReferenceId));
        assertTrue(source.referenceEmitted(ACTOR, sharedReferenceId));

        bytes32 promiseId = keccak256("promise");
        vm.recordLogs();
        vm.prank(ACTOR);
        source.executeRfq(
            promiseId, QUOTE_ID, beneficiary, INPUT_TOKEN, OUTPUT_TOKEN, INPUT_AMOUNT, MIN_OUTPUT_AMOUNT, RECIPIENT
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(source));
        assertEq(entries[0].topics[0], court.RFQ_EXECUTED());
        assertEq(entries[0].topics[2], QUOTE_ID);
        assertEq(entries[0].topics[3], _addressTopic(ACTOR));
        assertTrue(source.referenceEmitted(ACTOR, QUOTE_ID));
        assertTrue(source.promiseEmitted(ACTOR, promiseId));

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(DemoPromiseSource.PromiseAlreadyEmitted.selector, promiseId));
        source.executeRfq(
            promiseId,
            keccak256("new-quote"),
            beneficiary,
            INPUT_TOKEN,
            OUTPUT_TOKEN,
            INPUT_AMOUNT,
            MIN_OUTPUT_AMOUNT,
            RECIPIENT
        );

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(DemoPromiseSource.ReferenceAlreadyEmitted.selector, QUOTE_ID));
        source.releaseSettlement(keccak256("another-promise"), QUOTE_ID, SETTLEMENT_ASSET, RECIPIENT, 1 ether);

        vm.expectRevert(DemoPromiseSource.ZeroPromiseId.selector);
        source.releaseSettlement(bytes32(0), SETTLEMENT_ID, SETTLEMENT_ASSET, RECIPIENT, 1 ether);
        vm.expectRevert(DemoPromiseSource.ZeroReferenceId.selector);
        source.releaseSettlement(keccak256("promise"), bytes32(0), SETTLEMENT_ASSET, RECIPIENT, 1 ether);
    }

    function _openRfq(PromiseCourt.RfqTerms memory terms) private returns (bytes32 promiseId) {
        promiseId =
            _openPromise(PromiseBook.PromiseKind.RFQ_EXECUTION, court.RFQ_POLICY_ID(), court.rfqTermsHash(terms));
    }

    function _openSettlement(PromiseCourt.SettlementTerms memory terms) private returns (bytes32 promiseId) {
        promiseId = _openPromise(
            PromiseBook.PromiseKind.SETTLEMENT, court.SETTLEMENT_POLICY_ID(), court.settlementTermsHash(terms)
        );
    }

    function _openPromise(PromiseBook.PromiseKind kind, bytes32 policyId, bytes32 termsHash)
        private
        returns (bytes32 promiseId)
    {
        uint64 entropyBlock = uint64(block.number + 2);
        PromiseBook.DraftParams memory params = PromiseBook.DraftParams({
            kind: kind,
            beneficiary: beneficiary,
            sourceChainKey: CHAIN_KEY,
            sourceContract: address(source),
            policyId: policyId,
            adapterRevision: 1,
            termsHash: termsHash,
            activationLeadBlocks: 100,
            fulfillmentWindowBlocks: 101,
            proofSubmissionWindowBlocks: 100,
            entropyBlock: entropyBlock,
            activationDeadlineBlock: entropyBlock + 20,
            fixedPenalty: PENALTY,
            bond: BOND,
            beneficiaryNonce: authorizationNonce++
        });
        bytes32 digest = book.draftAuthorizationDigest(ACTOR, params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BENEFICIARY_KEY, digest);
        vm.prank(ACTOR);
        bytes32 draftId = book.registerDraft{ value: BOND }(params, bytes.concat(r, s, bytes1(v)));
        vm.roll(entropyBlock + book.MIN_ANCHOR_CONFIRMATIONS());
        vm.setBlockhash(entropyBlock, keccak256(abi.encode(ENTROPY_HASH, draftId)));
        promiseId = book.activateDraft(draftId);
    }

    function _proveRfq(
        bytes32 promiseId,
        PromiseCourt.RfqTerms memory terms,
        PromiseCourt.RfqExecution memory execution,
        uint64 height
    ) private returns (PromiseBook.Outcome outcome, uint256 reasons) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, execution);
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(height, encoded, false);
        (, outcome, reasons) = court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
    }

    function _proveSettlement(
        bytes32 promiseId,
        PromiseCourt.SettlementTerms memory terms,
        PromiseCourt.SettlementRelease memory release,
        uint64 height
    ) private returns (PromiseBook.Outcome outcome, uint256 reasons) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _settlementLog(address(source), promiseId, terms.settlementId, ACTOR, release);
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(height, encoded, false);
        (, outcome, reasons) = court.proveSettlementOutcome(promiseId, terms, context, inclusion, 0);
    }

    function _expectRfqGate(
        bytes32 promiseId,
        PromiseCourt.RfqTerms memory terms,
        EvmV1Decoder.LogEntryTuple memory selectedLog,
        bytes memory expectedRevert
    ) private {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = selectedLog;
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(1_150, encoded, false);
        vm.expectRevert(expectedRevert);
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
    }

    function _expectBookWindowRevert(
        bytes32 promiseId,
        PromiseCourt.RfqTerms memory terms,
        uint64 height,
        bytes memory expectedRevert
    ) private {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _rfqLog(address(source), promiseId, terms.quoteId, ACTOR, _validRfqExecution());
        bytes memory encoded = EvmV1Fixture.encodeType2(ACTOR, address(source), 1, logs);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(height, encoded, false);
        vm.expectRevert(expectedRevert);
        court.proveRfqOutcome(promiseId, terms, context, inclusion, 0);
    }

    function _prepare(uint64 blockHeight, bytes memory encoded, bool siblingOnLeft)
        private
        returns (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        )
    {
        chainInfo.setTip(CHAIN_KEY, blockHeight, true, true);
        context.chainKey = CHAIN_KEY;
        context.blockHeight = blockHeight;
        context.lowerEndpointDigest = keccak256(abi.encode("promise-lower-endpoint", blockHeight, encoded));
        context.continuityRoots = new bytes32[](1);
        context.continuityRoots[0] = keccak256(abi.encode("promise-continuity", blockHeight, encoded));

        inclusion.encodedTransaction = encoded;
        inclusion.merkleRoot = keccak256(abi.encode("promise-root", blockHeight, encoded));
        inclusion.siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        inclusion.siblings[0] = INativeQueryVerifier.MerkleProofEntry({
            hash: keccak256(abi.encode("promise-sibling", blockHeight, encoded)), isLeft: siblingOnLeft
        });

        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({ root: inclusion.merkleRoot, siblings: inclusion.siblings });
        INativeQueryVerifier.ContinuityProof memory continuityProof = INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: context.lowerEndpointDigest, roots: context.continuityRoots
        });
        verifier.allowProof(CHAIN_KEY, blockHeight, encoded, merkleProof, continuityProof);
    }

    function _rfqTerms() private pure returns (PromiseCourt.RfqTerms memory terms) {
        terms = PromiseCourt.RfqTerms({
            quoteId: QUOTE_ID,
            inputToken: INPUT_TOKEN,
            outputToken: OUTPUT_TOKEN,
            inputAmount: INPUT_AMOUNT,
            minOutputAmount: MIN_OUTPUT_AMOUNT,
            recipient: RECIPIENT
        });
    }

    function _settlementTerms() private pure returns (PromiseCourt.SettlementTerms memory terms) {
        terms = PromiseCourt.SettlementTerms({
            settlementId: SETTLEMENT_ID, asset: SETTLEMENT_ASSET, minAmount: MIN_SETTLEMENT_AMOUNT, recipient: RECIPIENT
        });
    }

    function _validRfqExecution() private view returns (PromiseCourt.RfqExecution memory execution) {
        execution = PromiseCourt.RfqExecution({
            beneficiary: beneficiary,
            inputToken: INPUT_TOKEN,
            outputToken: OUTPUT_TOKEN,
            inputAmount: INPUT_AMOUNT,
            outputAmount: MIN_OUTPUT_AMOUNT,
            recipient: RECIPIENT
        });
    }

    function _rfqLog(
        address emitter,
        bytes32 promiseId,
        bytes32 quoteId,
        address actor,
        PromiseCourt.RfqExecution memory execution
    ) private pure returns (EvmV1Decoder.LogEntryTuple memory logEntry) {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = keccak256("RFQExecuted(bytes32,bytes32,address,address,address,address,uint256,uint256,address)");
        topics[1] = promiseId;
        topics[2] = quoteId;
        topics[3] = _addressTopic(actor);
        logEntry = EvmV1Decoder.LogEntryTuple({
            address_: emitter,
            topics: topics,
            data: abi.encode(
                execution.beneficiary,
                execution.inputToken,
                execution.outputToken,
                execution.inputAmount,
                execution.outputAmount,
                execution.recipient
            )
        });
    }

    function _settlementLog(
        address emitter,
        bytes32 promiseId,
        bytes32 settlementId,
        address actor,
        PromiseCourt.SettlementRelease memory release
    ) private pure returns (EvmV1Decoder.LogEntryTuple memory logEntry) {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = keccak256("SettlementReleased(bytes32,bytes32,address,address,address,uint256)");
        topics[1] = promiseId;
        topics[2] = settlementId;
        topics[3] = _addressTopic(actor);
        logEntry = EvmV1Decoder.LogEntryTuple({
            address_: emitter, topics: topics, data: abi.encode(release.asset, release.recipient, release.amount)
        });
    }

    function _encodedTransaction(
        address from,
        address to,
        uint8 receiptStatus,
        EvmV1Decoder.LogEntryTuple[] memory logs,
        uint8 txType
    ) private pure returns (bytes memory encoded) {
        bytes[] memory chunks = new bytes[](3);
        chunks[0] = abi.encode(uint64(1), uint64(500_000), from, false, to, uint256(0), bytes(""));
        EvmV1Decoder.AccessListEntryBytes32[] memory accessList = new EvmV1Decoder.AccessListEntryBytes32[](0);
        chunks[1] = abi.encode(
            uint64(1), uint128(1 gwei), uint128(30 gwei), accessList, uint8(0), bytes32(uint256(1)), bytes32(uint256(2))
        );
        chunks[2] = abi.encode(receiptStatus, uint64(250_000), logs, bytes(""));
        encoded = abi.encode(txType, chunks);
    }

    function _addressTopic(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}
