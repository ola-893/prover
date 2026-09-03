// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    BureauEvidenceSBT,
    IAaveEvidenceView,
    ICovenantEvidenceView,
    IOrderingCourtEvidenceView
} from "../src/BureauEvidenceSBT.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { TestBase } from "./TestBase.sol";

contract MockEvidenceCovenantBook {
    mapping(bytes32 covenantId => ICovenantEvidenceView.Covenant covenant) private _covenants;

    function setCovenant(bytes32 covenantId, ICovenantEvidenceView.Covenant calldata covenant) external {
        _covenants[covenantId] = covenant;
    }

    function covenantOf(bytes32 covenantId) external view returns (ICovenantEvidenceView.Covenant memory) {
        return _covenants[covenantId];
    }
}

contract MockEvidenceOrderingCourt {
    address public immutable PERFORMANCE_BUREAU;
    address public immutable COVENANT_BOOK;

    mapping(bytes32 rulingId => IOrderingCourtEvidenceView.Ruling ruling) private _rulings;

    constructor(address bureau, address covenantBook) {
        PERFORMANCE_BUREAU = bureau;
        COVENANT_BOOK = covenantBook;
    }

    function setRuling(bytes32 rulingId, IOrderingCourtEvidenceView.Ruling calldata ruling) external {
        _rulings[rulingId] = ruling;
    }

    function rulingOf(bytes32 rulingId) external view returns (IOrderingCourtEvidenceView.Ruling memory) {
        return _rulings[rulingId];
    }

    function recordBreach(
        PerformanceBureau bureau,
        address subject,
        bytes32 evidenceId,
        PerformanceBureau.EvidenceKind kind,
        uint128 value,
        bool uncompensated
    ) external {
        bureau.recordEvidence(subject, evidenceId, kind, value, uncompensated);
    }
}

contract MockEvidenceAaveAdapter {
    address public immutable PERFORMANCE_BUREAU;

    mapping(bytes32 factId => IAaveEvidenceView.AaveFact fact) private _facts;
    mapping(bytes32 observationId => IAaveEvidenceView.SelfRepaymentObservation observation) private _observations;

    constructor(address bureau) {
        PERFORMANCE_BUREAU = bureau;
    }

    function setFact(bytes32 factId, IAaveEvidenceView.AaveFact calldata fact) external {
        _facts[factId] = fact;
    }

    function setObservation(bytes32 observationId, IAaveEvidenceView.SelfRepaymentObservation calldata observation)
        external
    {
        _observations[observationId] = observation;
    }

    function factOf(bytes32 factId) external view returns (IAaveEvidenceView.AaveFact memory) {
        return _facts[factId];
    }

    function observationOf(bytes32 observationId)
        external
        view
        returns (IAaveEvidenceView.SelfRepaymentObservation memory)
    {
        return _observations[observationId];
    }

    function recordObservation(PerformanceBureau bureau, bytes32 observationId) external {
        IAaveEvidenceView.SelfRepaymentObservation memory observation = _observations[observationId];
        bureau.recordEvidence(
            observation.subject,
            observationId,
            PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation,
            observation.matchedAmount,
            false
        );
    }
}

contract BureauEvidenceSBTTest is TestBase {
    PerformanceBureau internal bureau;
    MockEvidenceCovenantBook internal covenantBook;
    MockEvidenceOrderingCourt internal court;
    MockEvidenceAaveAdapter internal aaveAdapter;
    BureauEvidenceSBT internal evidenceSbt;

    address internal constant OPERATOR = address(0x0A11CE);
    address internal constant CLAIMANT = address(0xCA11A17);
    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant OTHER = address(0xB0B);
    address internal constant SOURCE = address(0x5150);
    address internal constant RESERVE = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 internal constant EVIDENCE_ID = keccak256("terminal-sandwich-ruling");
    bytes32 internal constant COVENANT_ID = keccak256("no-sandwich-covenant");
    bytes32 internal constant POLICY_ID = keccak256("no-sandwich-policy");
    bytes32 internal constant BORROW_TRANSACTION_EVIDENCE_ID = keccak256("borrow-transaction-evidence");
    bytes32 internal constant REPAY_TRANSACTION_EVIDENCE_ID = keccak256("repay-transaction-evidence");

    function setUp() public {
        bureau = new PerformanceBureau();
        covenantBook = new MockEvidenceCovenantBook();
        court = new MockEvidenceOrderingCourt(address(bureau), address(covenantBook));
        aaveAdapter = new MockEvidenceAaveAdapter(address(bureau));
        evidenceSbt = new BureauEvidenceSBT(address(bureau), address(court), address(aaveAdapter));

        uint256 breachMask = bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.FifoBreach);
        bureau.setReporterPermissions(address(court), breachMask);
        bureau.setReporterPermissions(
            address(aaveAdapter), bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation)
        );
    }

    function test_TransferFromRevertsOnMintedToken() public {
        _recordSandwichRuling(EVIDENCE_ID);

        vm.prank(OTHER);
        uint256 tokenId = evidenceSbt.mintFromEvidence(EVIDENCE_ID);
        assertEq(evidenceSbt.ownerOf(tokenId), CLAIMANT);
        assertTrue(evidenceSbt.locked(tokenId));

        vm.prank(CLAIMANT);
        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.TokenLocked.selector, tokenId));
        evidenceSbt.transferFrom(CLAIMANT, OTHER, tokenId);
    }

    function test_MintFromEvidenceRevertsOnNonexistentEvidenceId() public {
        bytes32 missing = keccak256("missing-evidence");
        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.EvidenceNotFound.selector, missing));
        evidenceSbt.mintFromEvidence(missing);
    }

    function test_BreachMintsToAffectedUserNotOperatorCallerOrBeneficiary() public {
        _recordSandwichRuling(EVIDENCE_ID);

        vm.prank(OTHER);
        uint256 tokenId = evidenceSbt.mintFromEvidence(EVIDENCE_ID);
        assertEq(evidenceSbt.ownerOf(tokenId), CLAIMANT);
        assertFalse(evidenceSbt.ownerOf(tokenId) == OPERATOR);
        assertFalse(evidenceSbt.ownerOf(tokenId) == OTHER);
        assertFalse(evidenceSbt.ownerOf(tokenId) == BENEFICIARY);

        BureauEvidenceSBT.EvidenceSnapshot memory snapshot = evidenceSbt.snapshotOf(EVIDENCE_ID);
        assertEq(snapshot.subject, OPERATOR);
        assertEq(snapshot.claimant, CLAIMANT);
        assertEq(snapshot.beneficiary, BENEFICIARY);
        assertEq(snapshot.covenantId, COVENANT_ID);
        assertEq(snapshot.policyId, POLICY_ID);
        assertEq(uint256(snapshot.damagesPaid), 10 ether);
        assertEq(snapshot.damagesShortfall, 2 ether);
        assertTrue(snapshot.uncompensated);
        assertFalse(snapshot.sourceTxIndexKnown);
        assertTrue(bytes(evidenceSbt.tokenURI(tokenId)).length > 29);
    }

    function test_SafeTransferAndApprovalsRevert() public {
        _recordSandwichRuling(EVIDENCE_ID);
        uint256 tokenId = evidenceSbt.mintFromEvidence(EVIDENCE_ID);

        vm.startPrank(CLAIMANT);
        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.TokenLocked.selector, tokenId));
        evidenceSbt.safeTransferFrom(CLAIMANT, OTHER, tokenId);
        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.TokenLocked.selector, tokenId));
        evidenceSbt.safeTransferFrom(CLAIMANT, OTHER, tokenId, "");
        vm.expectRevert(BureauEvidenceSBT.ApprovalsDisabled.selector);
        evidenceSbt.approve(OTHER, tokenId);
        vm.expectRevert(BureauEvidenceSBT.ApprovalsDisabled.selector);
        evidenceSbt.setApprovalForAll(OTHER, true);
        vm.stopPrank();
    }

    function test_SupportsERC5192Interface() public view {
        assertTrue(evidenceSbt.supportsInterface(0xb45a3c0e));
        assertTrue(evidenceSbt.supportsInterface(0x80ac58cd));
        assertTrue(evidenceSbt.supportsInterface(0x5b5e139f));
    }

    function test_PositiveObservationMintsToProvenSubjectWithBothCoordinates() public {
        bytes32 observationId = _recordPositiveObservation();

        vm.prank(OTHER);
        uint256 tokenId = evidenceSbt.mintFromEvidence(observationId);
        assertEq(evidenceSbt.ownerOf(tokenId), CLAIMANT);

        BureauEvidenceSBT.EvidenceSnapshot memory snapshot = evidenceSbt.snapshotOf(observationId);
        assertEq(snapshot.subject, CLAIMANT);
        assertEq(snapshot.reporter, address(aaveAdapter));
        assertEq(uint256(snapshot.verdict), uint256(BureauEvidenceSBT.Verdict.POSITIVE_OBSERVATION));
        assertEq(uint256(snapshot.sourceChainKey), 3);
        assertEq(uint256(snapshot.sourceBlockHeight), 25_854_707);
        assertEq(uint256(snapshot.sourceTxIndex), 201);
        assertEq(uint256(snapshot.sourceEndBlockHeight), 25_854_747);
        assertEq(uint256(snapshot.sourceEndTxIndex), 120);
        assertTrue(snapshot.sourceTxIndexKnown);
        assertTrue(snapshot.sourceEndCoordinateKnown);
    }

    function test_PositiveObservationRechecksRepaymentBounds() public {
        bytes32 observationId = _recordPositiveObservation();
        IAaveEvidenceView.SelfRepaymentObservation memory observation = aaveAdapter.observationOf(observationId);
        IAaveEvidenceView.AaveFact memory repay = aaveAdapter.factOf(observation.repayFactId);
        repay.amount = observation.matchedAmount - 1;
        aaveAdapter.setFact(observation.repayFactId, repay);

        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.InvalidPositiveObservation.selector, observationId));
        evidenceSbt.mintFromEvidence(observationId);
    }

    function test_LockedRevertsForNonexistentToken() public {
        uint256 tokenId = uint256(keccak256("not-minted"));
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ERC721NonexistentToken(uint256)")), tokenId));
        evidenceSbt.locked(tokenId);
    }

    function test_PositiveObservationFromUnpinnedReporterReverts() public {
        address reporter = address(0xA4A7E);
        bytes32 observationId = keccak256("untrusted-positive-observation");
        bureau.setReporterPermissions(
            reporter, bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation)
        );
        vm.prank(reporter);
        bureau.recordEvidence(
            CLAIMANT, observationId, PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 4_000e6, false
        );

        vm.expectRevert(
            abi.encodeWithSelector(BureauEvidenceSBT.WrongReporter.selector, address(aaveAdapter), reporter)
        );
        evidenceSbt.mintFromEvidence(observationId);
    }

    function test_RawAaveFactIsNotAFalseTerminalRecord() public {
        address reporter = address(0xA4A7E);
        bytes32 factId = keccak256("raw-borrow-fact");
        bureau.setReporterPermissions(reporter, bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveBorrow));
        vm.prank(reporter);
        bureau.recordEvidence(CLAIMANT, factId, PerformanceBureau.EvidenceKind.AaveBorrow, 4_000e6, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                BureauEvidenceSBT.EvidenceNotTerminal.selector, factId, PerformanceBureau.EvidenceKind.AaveBorrow
            )
        );
        evidenceSbt.mintFromEvidence(factId);
    }

    function test_DuplicateEvidenceCannotMintTwice() public {
        _recordSandwichRuling(EVIDENCE_ID);
        evidenceSbt.mintFromEvidence(EVIDENCE_ID);

        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.EvidenceAlreadyMinted.selector, EVIDENCE_ID));
        evidenceSbt.mintFromEvidence(EVIDENCE_ID);
    }

    function test_BreachFromUnpinnedReporterCannotChooseClaimant() public {
        address reporter = address(0xBAD);
        bytes32 evidenceId = keccak256("untrusted-breach");
        bureau.setReporterPermissions(reporter, bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach));
        vm.prank(reporter);
        bureau.recordEvidence(OPERATOR, evidenceId, PerformanceBureau.EvidenceKind.SandwichBreach, 10 ether, false);

        vm.expectRevert(abi.encodeWithSelector(BureauEvidenceSBT.WrongReporter.selector, address(court), reporter));
        evidenceSbt.mintFromEvidence(evidenceId);
    }

    function test_FifoKindMapsToFifoCovenantAndMintsAffectedUser() public {
        bytes32 evidenceId = keccak256("terminal-fifo-ruling");
        bytes32 covenantId = keccak256("fifo-covenant");
        _recordOrderingRuling(
            evidenceId,
            covenantId,
            IOrderingCourtEvidenceView.RulingKind.FIFO_INVERSION,
            ICovenantEvidenceView.CovenantType.FIFO,
            PerformanceBureau.EvidenceKind.FifoBreach
        );

        uint256 tokenId = evidenceSbt.mintFromEvidence(evidenceId);
        assertEq(evidenceSbt.ownerOf(tokenId), CLAIMANT);
        BureauEvidenceSBT.EvidenceSnapshot memory snapshot = evidenceSbt.snapshotOf(evidenceId);
        assertEq(uint256(snapshot.kind), uint256(PerformanceBureau.EvidenceKind.FifoBreach));
        assertEq(snapshot.engineSchemaId, evidenceSbt.FIFO_ENGINE_SCHEMA_ID());
    }

    function _recordSandwichRuling(bytes32 evidenceId) private {
        _recordOrderingRuling(
            evidenceId,
            COVENANT_ID,
            IOrderingCourtEvidenceView.RulingKind.SANDWICH,
            ICovenantEvidenceView.CovenantType.NO_SANDWICH,
            PerformanceBureau.EvidenceKind.SandwichBreach
        );
    }

    function _recordOrderingRuling(
        bytes32 evidenceId,
        bytes32 covenantId,
        IOrderingCourtEvidenceView.RulingKind rulingKind,
        ICovenantEvidenceView.CovenantType covenantType,
        PerformanceBureau.EvidenceKind evidenceKind
    ) private {
        vm.warp(1_000);
        covenantBook.setCovenant(
            covenantId,
            ICovenantEvidenceView.Covenant({
                operator: OPERATOR,
                sourceContract: SOURCE,
                policyHash: POLICY_ID,
                covenantType: covenantType,
                chainKey: 3,
                validFromHeight: 25_000_000,
                validUntilHeight: 26_000_000,
                claimDeadlineHeight: 26_050_400,
                breachCount: 1,
                fixedPenalty: 12 ether,
                initialBond: 30 ether,
                remainingBond: 20 ether,
                totalPaid: 10 ether,
                totalShortfall: 2 ether,
                bondReleased: false
            })
        );
        court.setRuling(
            evidenceId,
            IOrderingCourtEvidenceView.Ruling({
                covenantId: covenantId,
                kind: rulingKind,
                operator: OPERATOR,
                affectedUser: CLAIMANT,
                beneficiary: BENEFICIARY,
                breachHeight: 25_854_707,
                ruledAt: 900,
                paid: 10 ether,
                shortfall: 2 ether,
                bureauRecorded: true
            })
        );
        court.recordBreach(bureau, OPERATOR, evidenceId, evidenceKind, 10 ether, true);
    }

    function _recordPositiveObservation() private returns (bytes32 observationId) {
        vm.warp(1_000);
        bytes32 borrowFactId = keccak256(
            abi.encode("AAVE_USDC_FACT_V1", BORROW_TRANSACTION_EVIDENCE_ID, uint64(4), evidenceSbt.AAVE_BORROW())
        );
        bytes32 repayFactId = keccak256(
            abi.encode("AAVE_USDC_FACT_V1", REPAY_TRANSACTION_EVIDENCE_ID, uint64(4), evidenceSbt.AAVE_REPAY())
        );
        observationId = keccak256(abi.encode("AAVE_VERIFIED_SELF_REPAYMENT_V1", borrowFactId, repayFactId));

        aaveAdapter.setFact(
            borrowFactId,
            IAaveEvidenceView.AaveFact({
                kind: IAaveEvidenceView.FactKind.BORROW,
                subject: CLAIMANT,
                actor: OTHER,
                reserve: RESERVE,
                amount: 4_000e6,
                receiptLogOrdinal: 4,
                interestRateMode: 2,
                useATokens: false,
                position: IAaveEvidenceView.Position({ chainKey: 3, blockHeight: 25_854_707, txIndex: 201 }),
                transactionEvidenceId: BORROW_TRANSACTION_EVIDENCE_ID
            })
        );
        aaveAdapter.setFact(
            repayFactId,
            IAaveEvidenceView.AaveFact({
                kind: IAaveEvidenceView.FactKind.REPAY,
                subject: CLAIMANT,
                actor: CLAIMANT,
                reserve: RESERVE,
                amount: 4_100e6,
                receiptLogOrdinal: 4,
                interestRateMode: 0,
                useATokens: false,
                position: IAaveEvidenceView.Position({ chainKey: 3, blockHeight: 25_854_747, txIndex: 120 }),
                transactionEvidenceId: REPAY_TRANSACTION_EVIDENCE_ID
            })
        );
        aaveAdapter.setObservation(
            observationId,
            IAaveEvidenceView.SelfRepaymentObservation({
                subject: CLAIMANT,
                borrowFactId: borrowFactId,
                repayFactId: repayFactId,
                matchedAmount: 4_000e6,
                sourceBlockGap: 40
            })
        );
        aaveAdapter.recordObservation(bureau, observationId);
    }
}
