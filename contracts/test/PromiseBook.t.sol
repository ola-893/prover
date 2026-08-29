// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PromiseBook, IPromiseAttestedHeightSource } from "../src/PromiseBook.sol";
import { TestBase } from "./TestBase.sol";

contract MockPromiseAttestedHeightSource is IPromiseAttestedHeightSource {
    mapping(uint64 chainKey => HeightHashResult result) internal _tips;

    function setTip(uint64 chainKey, uint64 height, bool isAttestation, bool exists) external {
        _tips[chainKey] = HeightHashResult({
            height: height, hash: keccak256(abi.encode(chainKey, height)), isAttestation: isAttestation, exists: exists
        });
    }

    // Match the injected production precompile ABI.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_latest_attestation_height_and_hash(uint64 chainKey)
        external
        view
        returns (HeightHashResult memory result)
    {
        return _tips[chainKey];
    }
}

contract PromiseCourtCaller {
    function resolve(
        PromiseBook book,
        bytes32 promiseId,
        bytes32 evidenceId,
        uint64 evidenceHeight,
        PromiseBook.Outcome outcome
    ) external {
        book.resolveWithEvidence(promiseId, evidenceId, evidenceHeight, outcome);
    }
}

contract PromiseCreditReceiver {
    uint256 public received;

    function withdraw(PromiseBook book) external {
        book.withdrawCredit(payable(address(this)));
    }

    receive() external payable {
        received += msg.value;
    }
}

contract PromiseBookTest is TestBase {
    uint64 internal constant CHAIN_KEY = 1;
    uint64 internal constant INITIAL_TIP = 1_000;
    uint64 internal constant VALID_FROM = 1_100;
    uint64 internal constant FULFILLMENT_DEADLINE = 1_500;
    uint64 internal constant PROOF_DEADLINE = 1_700;

    address internal constant ACTOR = address(0xA11CE);
    address internal constant BENEFICIARY = address(0xB0B);
    address internal constant OTHER = address(0xBAD);
    address internal constant SOURCE = address(0x5150);
    bytes32 internal constant TERMS_HASH = keccak256("rfq-terms-v1");

    MockPromiseAttestedHeightSource internal chainInfo;
    PromiseCourtCaller internal promiseCourt;
    PromiseBook internal book;

    function setUp() public {
        chainInfo = new MockPromiseAttestedHeightSource();
        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true, true);
        promiseCourt = new PromiseCourtCaller();
        book = new PromiseBook(address(chainInfo));
        book.initializeCourt(address(promiseCourt));
        vm.deal(ACTOR, 1_000 ether);
    }

    function test_CourtCanOnlyBeInitializedOnceByDeployer() public {
        PromiseBook freshBook = new PromiseBook(address(chainInfo));

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.NotDeployer.selector, OTHER));
        freshBook.initializeCourt(address(promiseCourt));

        freshBook.initializeCourt(address(promiseCourt));
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.CourtAlreadyInitialized.selector, address(promiseCourt)));
        freshBook.initializeCourt(OTHER);
    }

    function test_CannotOpenBeforeCourtInitialization() public {
        PromiseBook freshBook = new PromiseBook(address(chainInfo));

        vm.prank(ACTOR);
        vm.expectRevert(PromiseBook.CourtNotInitialized.selector);
        freshBook.openPromise{ value: 10 ether }(
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            BENEFICIARY,
            CHAIN_KEY,
            SOURCE,
            VALID_FROM,
            FULFILLMENT_DEADLINE,
            PROOF_DEADLINE,
            TERMS_HASH,
            10 ether
        );
    }

    function test_RfqPromiseStoresImmutableTermsAndActorStats() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 30 ether, 10 ether);
        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);

        assertEq(record.terms.actor, ACTOR);
        assertEq(record.terms.beneficiary, BENEFICIARY);
        assertEq(record.terms.sourceContract, SOURCE);
        assertEq(record.terms.termsHash, TERMS_HASH);
        assertEq(uint256(record.terms.kind), uint256(PromiseBook.PromiseKind.RFQ_EXECUTION));
        assertEq(record.terms.sourceChainKey, CHAIN_KEY);
        assertEq(record.terms.validFromHeight, VALID_FROM);
        assertEq(record.terms.fulfillmentDeadlineHeight, FULFILLMENT_DEADLINE);
        assertEq(record.terms.proofDeadlineHeight, PROOF_DEADLINE);
        assertEq(record.terms.fixedPenalty, 10 ether);
        assertEq(record.terms.bond, 30 ether);
        assertEq(uint256(record.outcome), uint256(PromiseBook.Outcome.OPEN));

        (
            uint64 promisesOpened,
            uint64 promisesFulfilled,
            uint64 promisesBreached,
            uint64 promisesDefaulted,
            uint256 totalBondPosted,
            uint256 totalPenaltiesCharged
        ) = book.actorStats(ACTOR);
        assertEq(promisesOpened, 1);
        assertEq(promisesFulfilled, 0);
        assertEq(promisesBreached, 0);
        assertEq(promisesDefaulted, 0);
        assertEq(totalBondPosted, 30 ether);
        assertEq(totalPenaltiesCharged, 0);
    }

    function test_SettlementPromiseUsesSameGenericRegistry() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.SETTLEMENT, 20 ether, 8 ether);
        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);
        assertEq(uint256(record.terms.kind), uint256(PromiseBook.PromiseKind.SETTLEMENT));
        assertEq(record.terms.bond, 20 ether);
        assertEq(record.terms.fixedPenalty, 8 ether);
    }

    function test_OpeningRequiresFutureActivationOrderedDeadlinesAndAttestedChain() public {
        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.ActivationLeadTooShort.selector, uint64(1_063), uint64(1_064))
        );
        book.openPromise{ value: 10 ether }(
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            BENEFICIARY,
            CHAIN_KEY,
            SOURCE,
            1_063,
            FULFILLMENT_DEADLINE,
            PROOF_DEADLINE,
            TERMS_HASH,
            10 ether
        );

        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.FulfillmentDeadlineBeforeActivation.selector, VALID_FROM, VALID_FROM - 1)
        );
        book.openPromise{ value: 10 ether }(
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            BENEFICIARY,
            CHAIN_KEY,
            SOURCE,
            VALID_FROM,
            VALID_FROM - 1,
            PROOF_DEADLINE,
            TERMS_HASH,
            10 ether
        );

        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseBook.ProofDeadlineNotAfterFulfillment.selector, FULFILLMENT_DEADLINE, FULFILLMENT_DEADLINE
            )
        );
        book.openPromise{ value: 10 ether }(
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            BENEFICIARY,
            CHAIN_KEY,
            SOURCE,
            VALID_FROM,
            FULFILLMENT_DEADLINE,
            FULFILLMENT_DEADLINE,
            TERMS_HASH,
            10 ether
        );

        chainInfo.setTip(99, INITIAL_TIP, false, true);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.SourceChainNotAttested.selector, uint64(99)));
        book.openPromise{ value: 10 ether }(
            PromiseBook.PromiseKind.SETTLEMENT,
            BENEFICIARY,
            99,
            SOURCE,
            VALID_FROM,
            FULFILLMENT_DEADLINE,
            PROOF_DEADLINE,
            TERMS_HASH,
            10 ether
        );
    }

    function test_OpeningRequiresFixedPenaltyCoveredByBond() public {
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InsufficientBond.selector, 9 ether, 10 ether));
        book.openPromise{ value: 9 ether }(
            PromiseBook.PromiseKind.RFQ_EXECUTION,
            BENEFICIARY,
            CHAIN_KEY,
            SOURCE,
            VALID_FROM,
            FULFILLMENT_DEADLINE,
            PROOF_DEADLINE,
            TERMS_HASH,
            10 ether
        );
    }

    function test_OnlyCourtCanResolveWithEvidence() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 20 ether, 10 ether);
        chainInfo.setTip(CHAIN_KEY, 1_300, true, true);

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.WrongCourt.selector, OTHER, address(promiseCourt)));
        book.resolveWithEvidence(promiseId, keccak256("fill"), 1_200, PromiseBook.Outcome.FULFILLED);

        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidCourtOutcome.selector, PromiseBook.Outcome.DEFAULTED));
        promiseCourt.resolve(book, promiseId, keccak256("default"), 1_200, PromiseBook.Outcome.DEFAULTED);
    }

    function test_FulfillmentRefundsFullBondAndRecordsEvidence() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 30 ether, 10 ether);
        bytes32 evidenceId = keccak256("accepted-rfq-fill");
        chainInfo.setTip(CHAIN_KEY, 1_300, true, true);

        promiseCourt.resolve(book, promiseId, evidenceId, 1_200, PromiseBook.Outcome.FULFILLED);

        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);
        assertEq(uint256(record.outcome), uint256(PromiseBook.Outcome.FULFILLED));
        assertEq(record.evidenceId, evidenceId);
        assertEq(record.evidenceHeight, 1_200);
        assertEq(record.resolvedAtAttestedHeight, 1_300);
        assertTrue(book.usedEvidenceIds(evidenceId));
        assertEq(book.claimable(ACTOR), 30 ether);
        assertEq(book.claimable(BENEFICIARY), 0);

        (, uint64 fulfilled,,,, uint256 penalties) = book.actorStats(ACTOR);
        assertEq(fulfilled, 1);
        assertEq(penalties, 0);
    }

    function test_BreachCreditsFixedPenaltyAndRefundsResidual() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.SETTLEMENT, 30 ether, 10 ether);
        bytes32 evidenceId = keccak256("short-settlement");
        chainInfo.setTip(CHAIN_KEY, 1_600, true, true);

        promiseCourt.resolve(book, promiseId, evidenceId, 1_550, PromiseBook.Outcome.BREACHED);

        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);
        assertEq(uint256(record.outcome), uint256(PromiseBook.Outcome.BREACHED));
        assertEq(book.claimable(BENEFICIARY), 10 ether);
        assertEq(book.claimable(ACTOR), 20 ether);

        (,, uint64 breached,,, uint256 penalties) = book.actorStats(ACTOR);
        assertEq(breached, 1);
        assertEq(penalties, 10 ether);
    }

    function test_EvidenceHeightMustBeWithinOutcomeWindowAndAttested() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 20 ether, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.EvidenceBeforeActivation.selector, VALID_FROM - 1, VALID_FROM)
        );
        promiseCourt.resolve(book, promiseId, keccak256("early"), VALID_FROM - 1, PromiseBook.Outcome.FULFILLED);

        chainInfo.setTip(CHAIN_KEY, 1_400, true, true);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.EvidenceHeightNotAttested.selector, uint64(1_450), uint64(1_400))
        );
        promiseCourt.resolve(book, promiseId, keccak256("future"), 1_450, PromiseBook.Outcome.FULFILLED);

        chainInfo.setTip(CHAIN_KEY, 1_600, true, true);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.FulfillmentEvidenceLate.selector, uint64(1_501), FULFILLMENT_DEADLINE)
        );
        promiseCourt.resolve(book, promiseId, keccak256("late-fill"), 1_501, PromiseBook.Outcome.FULFILLED);

        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.BreachEvidenceAfterProofDeadline.selector, uint64(1_701), PROOF_DEADLINE)
        );
        promiseCourt.resolve(book, promiseId, keccak256("late-breach"), 1_701, PromiseBook.Outcome.BREACHED);
    }

    function test_EvidenceIdCannotResolveTwoPromises() public {
        bytes32 first = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 20 ether, 10 ether);
        bytes32 second = _open(PromiseBook.PromiseKind.SETTLEMENT, 20 ether, 10 ether);
        bytes32 evidenceId = keccak256("one-proof");
        chainInfo.setTip(CHAIN_KEY, 1_300, true, true);

        promiseCourt.resolve(book, first, evidenceId, 1_200, PromiseBook.Outcome.FULFILLED);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.EvidenceAlreadyUsed.selector, evidenceId));
        promiseCourt.resolve(book, second, evidenceId, 1_200, PromiseBook.Outcome.FULFILLED);
    }

    function test_CourtCannotResolveAfterProofWindowPasses() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.RFQ_EXECUTION, 20 ether, 10 ether);
        chainInfo.setTip(CHAIN_KEY, PROOF_DEADLINE + 1, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.ProofWindowClosed.selector, PROOF_DEADLINE + 1, PROOF_DEADLINE)
        );
        promiseCourt.resolve(book, promiseId, keccak256("late-proof"), 1_200, PromiseBook.Outcome.FULFILLED);
    }

    function test_DefaultIsPermissionlessOnlyAfterProofDeadlineAndMeansMissingAcceptableProof() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.SETTLEMENT, 30 ether, 10 ether);

        chainInfo.setTip(CHAIN_KEY, PROOF_DEADLINE, true, true);
        vm.prank(OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.ProofWindowStillOpen.selector, PROOF_DEADLINE, PROOF_DEADLINE)
        );
        book.finalizeProofSubmissionDefault(promiseId);

        chainInfo.setTip(CHAIN_KEY, PROOF_DEADLINE + 1, true, true);
        vm.prank(OTHER);
        book.finalizeProofSubmissionDefault(promiseId);

        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);
        assertEq(uint256(record.outcome), uint256(PromiseBook.Outcome.DEFAULTED));
        assertEq(record.evidenceId, bytes32(0));
        assertEq(record.evidenceHeight, 0);
        assertEq(record.resolvedAtAttestedHeight, PROOF_DEADLINE + 1);
        assertEq(book.claimable(BENEFICIARY), 10 ether);
        assertEq(book.claimable(ACTOR), 20 ether);

        (,,, uint64 defaulted,, uint256 penalties) = book.actorStats(ACTOR);
        assertEq(defaulted, 1);
        assertEq(penalties, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseBook.PromiseAlreadyResolved.selector, promiseId, PromiseBook.Outcome.DEFAULTED
            )
        );
        book.finalizeProofSubmissionDefault(promiseId);
    }

    function test_CreditsArePullBased() public {
        bytes32 promiseId = _open(PromiseBook.PromiseKind.SETTLEMENT, 30 ether, 10 ether);
        PromiseCreditReceiver receiver = new PromiseCreditReceiver();
        bytes32 evidenceId = keccak256("wrong-recipient");
        chainInfo.setTip(CHAIN_KEY, 1_300, true, true);

        promiseCourt.resolve(book, promiseId, evidenceId, 1_200, PromiseBook.Outcome.BREACHED);
        assertEq(receiver.received(), 0);

        uint256 beneficiaryBefore = BENEFICIARY.balance;
        vm.prank(BENEFICIARY);
        book.withdrawCredit(payable(BENEFICIARY));
        assertEq(BENEFICIARY.balance, beneficiaryBefore + 10 ether);

        uint256 actorBefore = ACTOR.balance;
        vm.prank(ACTOR);
        book.withdrawCredit(payable(ACTOR));
        assertEq(ACTOR.balance, actorBefore + 20 ether);
    }

    function _open(PromiseBook.PromiseKind kind, uint256 bond, uint256 penalty) private returns (bytes32 promiseId) {
        vm.prank(ACTOR);
        promiseId = book.openPromise{ value: bond }(
            kind, BENEFICIARY, CHAIN_KEY, SOURCE, VALID_FROM, FULFILLMENT_DEADLINE, PROOF_DEADLINE, TERMS_HASH, penalty
        );
    }
}
