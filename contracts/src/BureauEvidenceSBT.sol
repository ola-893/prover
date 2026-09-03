// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { PerformanceBureau } from "./PerformanceBureau.sol";
import { IERC5192 } from "./interfaces/IERC5192.sol";

/// @notice Read-only subset used to bind a breach token to one terminal ordering ruling.
interface IOrderingCourtEvidenceView {
    enum RulingKind {
        SANDWICH,
        FIFO_INVERSION
    }

    struct Ruling {
        bytes32 covenantId;
        RulingKind kind;
        address operator;
        address affectedUser;
        address beneficiary;
        uint64 breachHeight;
        uint64 ruledAt;
        uint256 paid;
        uint256 shortfall;
        bool bureauRecorded;
    }

    function PERFORMANCE_BUREAU() external view returns (address);
    function COVENANT_BOOK() external view returns (address);
    function rulingOf(bytes32 rulingId) external view returns (Ruling memory);
}

/// @notice Read-only immutable covenant fields used in evidence metadata.
interface ICovenantEvidenceView {
    enum CovenantType {
        NO_SANDWICH,
        FIFO
    }

    struct Covenant {
        address operator;
        address sourceContract;
        bytes32 policyHash;
        CovenantType covenantType;
        uint64 chainKey;
        uint64 validFromHeight;
        uint64 validUntilHeight;
        uint64 claimDeadlineHeight;
        uint32 breachCount;
        uint256 fixedPenalty;
        uint256 initialBond;
        uint256 remainingBond;
        uint256 totalPaid;
        uint256 totalShortfall;
        bool bondReleased;
    }

    function covenantOf(bytes32 covenantId) external view returns (Covenant memory);
}

/// @notice Read-only subset used to bind positive tokens to the pinned Aave reporter's facts.
interface IAaveEvidenceView {
    enum FactKind {
        NONE,
        BORROW,
        REPAY
    }

    struct Position {
        uint64 chainKey;
        uint64 blockHeight;
        uint64 txIndex;
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
        Position position;
        bytes32 transactionEvidenceId;
    }

    struct SelfRepaymentObservation {
        address subject;
        bytes32 borrowFactId;
        bytes32 repayFactId;
        uint128 matchedAmount;
        uint64 sourceBlockGap;
    }

    function PERFORMANCE_BUREAU() external view returns (address);
    function factOf(bytes32 factId) external view returns (AaveFact memory);
    function observationOf(bytes32 observationId) external view returns (SelfRepaymentObservation memory);
}

/// @title BureauEvidenceSBT
/// @notice Permissionless, non-transferable display receipts for terminal PerformanceBureau evidence.
/// @dev PerformanceBureau remains the canonical issuance gate. The fixed reporter contracts are
///      read only to recover and cross-check immutable details that the compact bureau record does
///      not retain. This contract creates no verdict, payout, reporter permission or profile change.
contract BureauEvidenceSBT is ERC721, IERC5192 {
    using Strings for address;
    using Strings for uint256;

    enum Verdict {
        POSITIVE_OBSERVATION,
        BREACH
    }

    struct EvidenceSnapshot {
        address subject;
        address claimant;
        address beneficiary;
        address reporter;
        address court;
        bytes32 covenantId;
        bytes32 policyId;
        bytes32 engineSchemaId;
        bytes32 sourceTransactionEvidenceId;
        bytes32 sourceEndTransactionEvidenceId;
        PerformanceBureau.EvidenceKind kind;
        Verdict verdict;
        uint64 recordedAt;
        uint64 ruledAt;
        uint64 sourceChainKey;
        uint64 sourceBlockHeight;
        uint64 sourceTxIndex;
        uint64 sourceReceiptLogOrdinal;
        uint64 sourceEndBlockHeight;
        uint64 sourceEndTxIndex;
        uint64 sourceEndReceiptLogOrdinal;
        uint128 evidenceValue;
        uint128 damagesPaid;
        uint256 damagesShortfall;
        bool uncompensated;
        bool sourceTxIndexKnown;
        bool sourceEndCoordinateKnown;
    }

    bytes4 public constant ERC5192_INTERFACE_ID = 0xb45a3c0e;
    bytes32 public constant AAVE_SELF_REPAYMENT_SCHEMA_ID = keccak256("AAVE_VERIFIED_SELF_REPAYMENT_V1");
    bytes32 public constant SANDWICH_ENGINE_SCHEMA_ID = keccak256("ORDERING_COURT_SANDWICH_V1");
    bytes32 public constant FIFO_ENGINE_SCHEMA_ID = keccak256("ORDERING_COURT_FIFO_V1");
    bytes32 public constant AAVE_BORROW = keccak256("Borrow(address,address,address,uint256,uint8,uint256,uint16)");
    bytes32 public constant AAVE_REPAY = keccak256("Repay(address,address,address,uint256,bool)");
    uint64 public constant ETHEREUM_MAINNET_CHAIN_KEY = 3;
    uint64 public constant MINIMUM_SELF_REPAYMENT_BLOCK_GAP = 32;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    PerformanceBureau public immutable PERFORMANCE_BUREAU;
    IOrderingCourtEvidenceView public immutable ORDERING_COURT;
    ICovenantEvidenceView public immutable COVENANT_BOOK;
    IAaveEvidenceView public immutable AAVE_ADAPTER;

    mapping(uint256 tokenId => EvidenceSnapshot snapshot) private _snapshots;

    event EvidenceTokenMinted(
        bytes32 indexed evidenceId,
        uint256 indexed tokenId,
        address indexed recipient,
        address subject,
        PerformanceBureau.EvidenceKind kind,
        Verdict verdict
    );

    error ZeroAddress();
    error DependencyHasNoCode(address dependency);
    error ReporterBureauMismatch(address reporter, address expected, address actual);
    error EvidenceNotFound(bytes32 evidenceId);
    error EvidenceNotTerminal(bytes32 evidenceId, PerformanceBureau.EvidenceKind kind);
    error EvidenceAlreadyMinted(bytes32 evidenceId);
    error WrongReporter(address expected, address actual);
    error RulingNotFound(bytes32 evidenceId);
    error RulingNotRecorded(bytes32 evidenceId);
    error RulingKindMismatch(
        PerformanceBureau.EvidenceKind evidenceKind, IOrderingCourtEvidenceView.RulingKind rulingKind
    );
    error RulingSubjectMismatch(address evidenceSubject, address rulingOperator);
    error InvalidRulingParticipant(bytes32 evidenceId);
    error RulingValueDoesNotFit(uint256 paid);
    error RulingValueMismatch(uint128 evidenceValue, uint256 rulingPaid);
    error RulingShortfallMismatch(bool evidenceUncompensated, uint256 rulingShortfall);
    error RulingTimestampMismatch(uint64 recordedAt, uint64 ruledAt);
    error CovenantMismatch(bytes32 covenantId);
    error InvalidPositiveObservation(bytes32 evidenceId);
    error TokenLocked(uint256 tokenId);
    error ApprovalsDisabled();

    constructor(address performanceBureau, address orderingCourt, address aaveAdapter)
        ERC721("Prover Evidence", "PROOF")
    {
        if (performanceBureau == address(0) || orderingCourt == address(0) || aaveAdapter == address(0)) {
            revert ZeroAddress();
        }
        _requireCode(performanceBureau);
        _requireCode(orderingCourt);
        _requireCode(aaveAdapter);

        PERFORMANCE_BUREAU = PerformanceBureau(performanceBureau);
        ORDERING_COURT = IOrderingCourtEvidenceView(orderingCourt);
        AAVE_ADAPTER = IAaveEvidenceView(aaveAdapter);

        _requireReporterBureau(orderingCourt, ORDERING_COURT.PERFORMANCE_BUREAU(), performanceBureau);
        _requireReporterBureau(aaveAdapter, AAVE_ADAPTER.PERFORMANCE_BUREAU(), performanceBureau);

        address covenantBook = ORDERING_COURT.COVENANT_BOOK();
        if (covenantBook == address(0)) revert ZeroAddress();
        _requireCode(covenantBook);
        COVENANT_BOOK = ICovenantEvidenceView(covenantBook);
    }

    /// @notice Mints the one token corresponding to an already-recorded terminal evidence ID.
    /// @dev Anyone may submit the transaction, but the caller never chooses the recipient or data.
    ///      A positive observation is bound to its proven subject. An ordering breach is bound to
    ///      the proof-derived affected user; the responsible operator remains `snapshot.subject`.
    function mintFromEvidence(bytes32 evidenceId) external returns (uint256 tokenId) {
        if (!PERFORMANCE_BUREAU.evidenceRecorded(evidenceId)) revert EvidenceNotFound(evidenceId);

        tokenId = tokenIdFor(evidenceId);
        if (_ownerOf(tokenId) != address(0)) revert EvidenceAlreadyMinted(evidenceId);

        PerformanceBureau.EvidenceMeta memory meta = PERFORMANCE_BUREAU.evidenceOf(evidenceId);
        EvidenceSnapshot memory snapshot;
        address recipient;

        if (meta.kind == PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation) {
            (snapshot, recipient) = _positiveSnapshot(evidenceId, meta);
        } else if (
            meta.kind == PerformanceBureau.EvidenceKind.SandwichBreach
                || meta.kind == PerformanceBureau.EvidenceKind.FifoBreach
        ) {
            (snapshot, recipient) = _breachSnapshot(evidenceId, meta);
        } else {
            revert EvidenceNotTerminal(evidenceId, meta.kind);
        }

        _snapshots[tokenId] = snapshot;
        _mint(recipient, tokenId);
        emit Locked(tokenId);
        emit EvidenceTokenMinted(evidenceId, tokenId, recipient, snapshot.subject, snapshot.kind, snapshot.verdict);
    }

    function tokenIdFor(bytes32 evidenceId) public pure returns (uint256) {
        return uint256(evidenceId);
    }

    function snapshotOf(bytes32 evidenceId) external view returns (EvidenceSnapshot memory snapshot) {
        uint256 tokenId = tokenIdFor(evidenceId);
        _requireOwned(tokenId);
        return _snapshots[tokenId];
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) public view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == ERC5192_INTERFACE_ID || interfaceId == type(IERC5192).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        EvidenceSnapshot memory snapshot = _snapshots[tokenId];
        bytes32 evidenceId = bytes32(tokenId);

        bytes memory json = abi.encodePacked(
            '{"name":"Prover Evidence - ',
            _kindLabel(snapshot.kind),
            '","description":"',
            _description(snapshot.verdict),
            '"'
        );
        json = abi.encodePacked(
            json,
            ',"evidence_id":"',
            _bytes32String(evidenceId),
            '","engine":"',
            _engine(snapshot.kind),
            '","engine_version":"',
            _engineVersion(snapshot.kind),
            '","metadata_schema_version":"1"'
        );
        json = abi.encodePacked(
            json,
            ',"proof_statement":"',
            _proofStatement(snapshot.kind),
            '","subject":"',
            snapshot.subject.toHexString(),
            '","claimant":',
            _nullableAddress(snapshot.claimant),
            ',"claimant_role":"',
            snapshot.verdict == Verdict.BREACH ? "proof-derived affected user, not proof submitter" : "none",
            '"'
        );
        json = abi.encodePacked(
            json,
            ',"beneficiary":',
            _nullableAddress(snapshot.beneficiary),
            ',"covenant_id":',
            _nullableBytes32(snapshot.covenantId),
            ',"source_chain_key":',
            uint256(snapshot.sourceChainKey).toString(),
            ',"source_block_height":',
            uint256(snapshot.sourceBlockHeight).toString()
        );
        json = abi.encodePacked(
            json,
            ',"source_tx_index":',
            snapshot.sourceTxIndexKnown ? uint256(snapshot.sourceTxIndex).toString() : "null",
            ',"source_receipt_log_ordinal":',
            snapshot.sourceTxIndexKnown ? uint256(snapshot.sourceReceiptLogOrdinal).toString() : "null",
            ',"source_tx_index_known":',
            snapshot.sourceTxIndexKnown ? "true" : "false"
        );
        json = abi.encodePacked(
            json,
            ',"source_end_block_height":',
            snapshot.sourceEndCoordinateKnown ? uint256(snapshot.sourceEndBlockHeight).toString() : "null",
            ',"source_end_tx_index":',
            snapshot.sourceEndCoordinateKnown ? uint256(snapshot.sourceEndTxIndex).toString() : "null",
            ',"source_end_receipt_log_ordinal":',
            snapshot.sourceEndCoordinateKnown ? uint256(snapshot.sourceEndReceiptLogOrdinal).toString() : "null"
        );
        json = abi.encodePacked(
            json,
            ',"source_transaction_evidence_id":',
            _nullableBytes32(snapshot.sourceTransactionEvidenceId),
            ',"source_end_transaction_evidence_id":',
            _nullableBytes32(snapshot.sourceEndTransactionEvidenceId),
            ',"verdict":"',
            _verdictLabel(snapshot.verdict),
            '"'
        );
        json = abi.encodePacked(
            json,
            ',"evidence_value":"',
            uint256(snapshot.evidenceValue).toString(),
            '","evidence_value_unit":"',
            snapshot.verdict == Verdict.BREACH ? "CTC wei (18 decimals)" : "USDC base units (6 decimals)",
            '","damages_paid":"',
            uint256(snapshot.damagesPaid).toString(),
            '","damages_shortfall":"',
            snapshot.damagesShortfall.toString(),
            '"'
        );
        json = abi.encodePacked(
            json,
            ',"damages_unit":"',
            snapshot.verdict == Verdict.BREACH ? "CTC wei (18 decimals)" : "none",
            '","court":',
            _nullableAddress(snapshot.court),
            ',"reporter":"',
            snapshot.reporter.toHexString(),
            '","policy_id":',
            _nullableBytes32(snapshot.policyId),
            ',"engine_schema_id":"',
            _bytes32String(snapshot.engineSchemaId),
            '"'
        );
        json = abi.encodePacked(
            json,
            ',"recorded_at":',
            uint256(snapshot.recordedAt).toString(),
            ',"ruled_at":',
            snapshot.ruledAt == 0 ? "null" : uint256(snapshot.ruledAt).toString(),
            ',"uncompensated":',
            snapshot.uncompensated ? "true" : "false",
            ',"canonical_bureau":"',
            address(PERFORMANCE_BUREAU).toHexString(),
            '","transferability":"soulbound"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    /// @dev ERC-5192 requires every ERC-721 transfer path to throw while `locked` is true.
    function transferFrom(address, address, uint256 tokenId) public view override {
        if (locked(tokenId)) revert TokenLocked(tokenId);
    }

    /// @dev The inherited three-argument safeTransferFrom dispatches to this virtual overload.
    function safeTransferFrom(address, address, uint256 tokenId, bytes memory) public view override {
        if (locked(tokenId)) revert TokenLocked(tokenId);
    }

    function approve(address, uint256) public pure override {
        revert ApprovalsDisabled();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert ApprovalsDisabled();
    }

    /// @dev Defense in depth: no inherited or future internal route may transfer or burn a token.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address previousOwner) {
        if (_ownerOf(tokenId) != address(0)) revert TokenLocked(tokenId);
        return super._update(to, tokenId, auth);
    }

    function _positiveSnapshot(bytes32 evidenceId, PerformanceBureau.EvidenceMeta memory meta)
        private
        view
        returns (EvidenceSnapshot memory snapshot, address recipient)
    {
        if (meta.reporter != address(AAVE_ADAPTER)) revert WrongReporter(address(AAVE_ADAPTER), meta.reporter);
        if (meta.subject == address(0) || meta.value == 0 || meta.uncompensated || meta.recordedAt == 0) {
            revert InvalidPositiveObservation(evidenceId);
        }

        IAaveEvidenceView.SelfRepaymentObservation memory observation = AAVE_ADAPTER.observationOf(evidenceId);
        IAaveEvidenceView.AaveFact memory borrow = AAVE_ADAPTER.factOf(observation.borrowFactId);
        IAaveEvidenceView.AaveFact memory repay = AAVE_ADAPTER.factOf(observation.repayFactId);

        bytes32 expectedBorrowFactId = keccak256(
            abi.encode("AAVE_USDC_FACT_V1", borrow.transactionEvidenceId, borrow.receiptLogOrdinal, AAVE_BORROW)
        );
        bytes32 expectedRepayFactId = keccak256(
            abi.encode("AAVE_USDC_FACT_V1", repay.transactionEvidenceId, repay.receiptLogOrdinal, AAVE_REPAY)
        );
        bytes32 expectedObservationId =
            keccak256(abi.encode("AAVE_VERIFIED_SELF_REPAYMENT_V1", observation.borrowFactId, observation.repayFactId));

        bool ordered = borrow.position.chainKey == repay.position.chainKey
            && (borrow.position.blockHeight < repay.position.blockHeight
                || (borrow.position.blockHeight == repay.position.blockHeight
                    && borrow.position.txIndex < repay.position.txIndex));
        bool validFacts = borrow.kind == IAaveEvidenceView.FactKind.BORROW
            && repay.kind == IAaveEvidenceView.FactKind.REPAY && borrow.subject == meta.subject
            && repay.subject == meta.subject && repay.actor == meta.subject && borrow.reserve == repay.reserve
            && borrow.reserve == USDC && borrow.position.chainKey == ETHEREUM_MAINNET_CHAIN_KEY
            && repay.position.chainKey == ETHEREUM_MAINNET_CHAIN_KEY && repay.amount >= borrow.amount
            && observation.sourceBlockGap >= MINIMUM_SELF_REPAYMENT_BLOCK_GAP
            && borrow.amount == observation.matchedAmount && observation.subject == meta.subject
            && observation.matchedAmount == meta.value && borrow.transactionEvidenceId != bytes32(0)
            && repay.transactionEvidenceId != bytes32(0) && expectedBorrowFactId == observation.borrowFactId
            && expectedRepayFactId == observation.repayFactId && expectedObservationId == evidenceId && ordered
            && repay.position.blockHeight - borrow.position.blockHeight == observation.sourceBlockGap;
        if (!validFacts) revert InvalidPositiveObservation(evidenceId);

        recipient = meta.subject;
        snapshot = EvidenceSnapshot({
            subject: meta.subject,
            claimant: address(0),
            beneficiary: address(0),
            reporter: meta.reporter,
            court: address(0),
            covenantId: bytes32(0),
            policyId: bytes32(0),
            engineSchemaId: AAVE_SELF_REPAYMENT_SCHEMA_ID,
            sourceTransactionEvidenceId: borrow.transactionEvidenceId,
            sourceEndTransactionEvidenceId: repay.transactionEvidenceId,
            kind: meta.kind,
            verdict: Verdict.POSITIVE_OBSERVATION,
            recordedAt: meta.recordedAt,
            ruledAt: 0,
            sourceChainKey: borrow.position.chainKey,
            sourceBlockHeight: borrow.position.blockHeight,
            sourceTxIndex: borrow.position.txIndex,
            sourceReceiptLogOrdinal: borrow.receiptLogOrdinal,
            sourceEndBlockHeight: repay.position.blockHeight,
            sourceEndTxIndex: repay.position.txIndex,
            sourceEndReceiptLogOrdinal: repay.receiptLogOrdinal,
            evidenceValue: meta.value,
            damagesPaid: 0,
            damagesShortfall: 0,
            uncompensated: false,
            sourceTxIndexKnown: true,
            sourceEndCoordinateKnown: true
        });
    }

    function _breachSnapshot(bytes32 evidenceId, PerformanceBureau.EvidenceMeta memory meta)
        private
        view
        returns (EvidenceSnapshot memory snapshot, address recipient)
    {
        if (meta.reporter != address(ORDERING_COURT)) {
            revert WrongReporter(address(ORDERING_COURT), meta.reporter);
        }

        IOrderingCourtEvidenceView.Ruling memory ruling = ORDERING_COURT.rulingOf(evidenceId);
        if (ruling.covenantId == bytes32(0)) revert RulingNotFound(evidenceId);
        if (!ruling.bureauRecorded) revert RulingNotRecorded(evidenceId);
        if (ruling.operator == address(0) || ruling.affectedUser == address(0) || ruling.beneficiary == address(0)) {
            revert InvalidRulingParticipant(evidenceId);
        }
        if (ruling.operator != meta.subject) revert RulingSubjectMismatch(meta.subject, ruling.operator);

        PerformanceBureau.EvidenceKind expectedKind = ruling.kind == IOrderingCourtEvidenceView.RulingKind.SANDWICH
            ? PerformanceBureau.EvidenceKind.SandwichBreach
            : PerformanceBureau.EvidenceKind.FifoBreach;
        if (meta.kind != expectedKind) revert RulingKindMismatch(meta.kind, ruling.kind);
        if (ruling.paid > type(uint128).max) revert RulingValueDoesNotFit(ruling.paid);
        if (meta.value != uint128(ruling.paid)) revert RulingValueMismatch(meta.value, ruling.paid);
        if (meta.uncompensated != (ruling.shortfall != 0)) {
            revert RulingShortfallMismatch(meta.uncompensated, ruling.shortfall);
        }
        if (ruling.ruledAt == 0 || meta.recordedAt < ruling.ruledAt) {
            revert RulingTimestampMismatch(meta.recordedAt, ruling.ruledAt);
        }

        ICovenantEvidenceView.Covenant memory covenant = COVENANT_BOOK.covenantOf(ruling.covenantId);
        ICovenantEvidenceView.CovenantType expectedCovenantType = ruling.kind
            == IOrderingCourtEvidenceView.RulingKind.SANDWICH
            ? ICovenantEvidenceView.CovenantType.NO_SANDWICH
            : ICovenantEvidenceView.CovenantType.FIFO;
        bool moneyMatches =
            ruling.paid <= covenant.fixedPenalty && ruling.shortfall == covenant.fixedPenalty - ruling.paid;
        if (
            covenant.operator != ruling.operator || covenant.sourceContract == address(0)
                || covenant.covenantType != expectedCovenantType || covenant.policyHash == bytes32(0)
                || ruling.breachHeight < covenant.validFromHeight || ruling.breachHeight > covenant.validUntilHeight
                || !moneyMatches
        ) {
            revert CovenantMismatch(ruling.covenantId);
        }

        recipient = ruling.affectedUser;
        bytes32 engineSchemaId = ruling.kind == IOrderingCourtEvidenceView.RulingKind.SANDWICH
            ? SANDWICH_ENGINE_SCHEMA_ID
            : FIFO_ENGINE_SCHEMA_ID;
        snapshot = EvidenceSnapshot({
            subject: meta.subject,
            claimant: ruling.affectedUser,
            beneficiary: ruling.beneficiary,
            reporter: meta.reporter,
            court: address(ORDERING_COURT),
            covenantId: ruling.covenantId,
            policyId: covenant.policyHash,
            engineSchemaId: engineSchemaId,
            sourceTransactionEvidenceId: bytes32(0),
            sourceEndTransactionEvidenceId: bytes32(0),
            kind: meta.kind,
            verdict: Verdict.BREACH,
            recordedAt: meta.recordedAt,
            ruledAt: ruling.ruledAt,
            sourceChainKey: covenant.chainKey,
            sourceBlockHeight: ruling.breachHeight,
            sourceTxIndex: 0,
            sourceReceiptLogOrdinal: 0,
            sourceEndBlockHeight: 0,
            sourceEndTxIndex: 0,
            sourceEndReceiptLogOrdinal: 0,
            evidenceValue: meta.value,
            damagesPaid: uint128(ruling.paid),
            damagesShortfall: ruling.shortfall,
            uncompensated: meta.uncompensated,
            sourceTxIndexKnown: false,
            sourceEndCoordinateKnown: false
        });
    }

    function _requireCode(address dependency) private view {
        if (dependency.code.length == 0) revert DependencyHasNoCode(dependency);
    }

    function _requireReporterBureau(address reporter, address actual, address expected) private pure {
        if (actual != expected) revert ReporterBureauMismatch(reporter, expected, actual);
    }

    function _kindLabel(PerformanceBureau.EvidenceKind kind) private pure returns (string memory) {
        if (kind == PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation) return "Aave self-repayment";
        if (kind == PerformanceBureau.EvidenceKind.SandwichBreach) return "Sandwich breach";
        return "FIFO breach";
    }

    function _engine(PerformanceBureau.EvidenceKind kind) private pure returns (string memory) {
        if (kind == PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation) return "AaveEvidenceAdapter";
        return "OrderingCourt";
    }

    function _engineVersion(PerformanceBureau.EvidenceKind kind) private pure returns (string memory) {
        if (kind == PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation) return "aave-self-repayment-v1";
        if (kind == PerformanceBureau.EvidenceKind.SandwichBreach) return "ordering-sandwich-v1";
        return "ordering-fifo-v1";
    }

    function _proofStatement(PerformanceBureau.EvidenceKind kind) private pure returns (string memory) {
        if (kind == PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation) {
            return "Authenticated Aave USDC Borrow followed by a same-subject, same-or-larger self-funded Repay under the adapter's bounded predicate.";
        }
        if (kind == PerformanceBureau.EvidenceKind.SandwichBreach) {
            return "Three authenticated adjacent swaps satisfied the policy-bound no-sandwich breach predicate.";
        }
        return "Authenticated exit events proved that a later request was completed before an earlier request under the FIFO covenant.";
    }

    function _verdictLabel(Verdict verdict) private pure returns (string memory) {
        return verdict == Verdict.BREACH ? "BREACHED" : "POSITIVE_OBSERVATION";
    }

    function _description(Verdict verdict) private pure returns (string memory) {
        if (verdict == Verdict.BREACH) {
            return "A non-transferable receipt held by the proof-derived affected user for an ordering breach already recorded by PerformanceBureau. The holder is not necessarily the proof submitter or payout beneficiary; the bureau and court remain canonical.";
        }
        return "A non-transferable display record for one bounded self-repayment observation already recorded by PerformanceBureau. It is not proof of loan closure, solvency, or complete credit history.";
    }

    function _nullableAddress(address value) private pure returns (string memory) {
        return value == address(0) ? "null" : string.concat('"', value.toHexString(), '"');
    }

    function _nullableBytes32(bytes32 value) private pure returns (string memory) {
        return value == bytes32(0) ? "null" : string.concat('"', _bytes32String(value), '"');
    }

    function _bytes32String(bytes32 value) private pure returns (string memory) {
        return Strings.toHexString(uint256(value), 32);
    }
}
