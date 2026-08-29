// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Exact subset of Creditcoin's ChainInfo precompile used by PromiseBook.
/// @dev Production deployments inject 0x0000000000000000000000000000000000000fD3.
///      Tests inject a deterministic mock with the same ABI.
interface IPromiseAttestedHeightSource {
    struct HeightHashResult {
        uint64 height;
        bytes32 hash;
        bool isAttestation;
        bool exists;
    }

    // Exact snake-case ABI shipped by the ChainInfo precompile.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_latest_attestation_height_and_hash(uint64 chainKey)
        external
        view
        returns (HeightHashResult memory result);
}

/// @title PromiseBook
/// @notice Immutable, bonded RFQ-execution and settlement promises resolved from source-chain evidence.
/// @dev Promise terms cannot be edited or cancelled. The court authenticates evidence and its source height;
///      this book enforces the committed height windows, terminal outcomes, replay protection and payouts.
///      DEFAULTED means no acceptable proof was resolved on this book by the proof deadline. It does not prove
///      that a fulfillment transaction or any other event did not occur on the source chain.
contract PromiseBook {
    /// @notice Minimum lead beyond the latest attested source height when a promise is opened.
    uint64 public constant MIN_ATTESTED_LEAD_BLOCKS = 64;

    enum PromiseKind {
        RFQ_EXECUTION,
        SETTLEMENT
    }

    enum Outcome {
        OPEN,
        FULFILLED,
        BREACHED,
        DEFAULTED
    }

    struct PromiseTerms {
        address actor;
        address beneficiary;
        address sourceContract;
        bytes32 termsHash;
        PromiseKind kind;
        uint64 sourceChainKey;
        uint64 validFromHeight;
        uint64 fulfillmentDeadlineHeight;
        uint64 proofDeadlineHeight;
        uint256 fixedPenalty;
        uint256 bond;
    }

    struct PromiseRecord {
        PromiseTerms terms;
        Outcome outcome;
        bytes32 evidenceId;
        uint64 evidenceHeight;
        uint64 resolvedAtAttestedHeight;
    }

    struct ActorStats {
        uint64 promisesOpened;
        uint64 promisesFulfilled;
        uint64 promisesBreached;
        uint64 promisesDefaulted;
        uint256 totalBondPosted;
        uint256 totalPenaltiesCharged;
    }

    IPromiseAttestedHeightSource public immutable CHAIN_INFO;
    address public immutable DEPLOYER;
    address public court;

    mapping(address actor => uint64 nonce) public nextNonce;
    mapping(address actor => ActorStats stats) public actorStats;
    mapping(bytes32 evidenceId => bool used) public usedEvidenceIds;
    mapping(address account => uint256 amount) public claimable;
    mapping(bytes32 promiseId => PromiseRecord record) private _promises;

    uint256 private _entered;

    event CourtInitialized(address indexed court);
    event PromiseOpened(
        bytes32 indexed promiseId,
        PromiseKind indexed kind,
        address indexed actor,
        address beneficiary,
        uint64 sourceChainKey,
        address sourceContract,
        uint64 validFromHeight,
        uint64 fulfillmentDeadlineHeight,
        uint64 proofDeadlineHeight,
        bytes32 termsHash,
        uint256 fixedPenalty,
        uint256 bond
    );
    event PromiseResolved(
        bytes32 indexed promiseId,
        Outcome indexed outcome,
        bytes32 indexed evidenceId,
        uint64 evidenceHeight,
        uint64 resolvedAtAttestedHeight,
        uint256 beneficiaryCredit,
        uint256 actorCredit
    );
    event ProofSubmissionDefaultFinalized(
        bytes32 indexed promiseId,
        address indexed actor,
        address indexed beneficiary,
        uint64 proofDeadlineHeight,
        uint64 resolvedAtAttestedHeight,
        uint256 beneficiaryCredit,
        uint256 actorCredit
    );
    event CreditWithdrawn(address indexed account, address indexed recipient, uint256 amount);

    error ZeroAddress();
    error ZeroTermsHash();
    error ZeroPenalty();
    error InsufficientBond(uint256 supplied, uint256 minimum);
    error SourceChainNotAttested(uint64 sourceChainKey);
    error HeightOverflow();
    error ActivationLeadTooShort(uint64 requestedHeight, uint64 minimumHeight);
    error FulfillmentDeadlineBeforeActivation(uint64 validFromHeight, uint64 fulfillmentDeadlineHeight);
    error ProofDeadlineNotAfterFulfillment(uint64 fulfillmentDeadlineHeight, uint64 proofDeadlineHeight);
    error NotDeployer(address caller);
    error CourtAlreadyInitialized(address court);
    error CourtNotInitialized();
    error WrongCourt(address caller, address expected);
    error PromiseNotFound(bytes32 promiseId);
    error PromiseAlreadyResolved(bytes32 promiseId, Outcome outcome);
    error ZeroEvidenceId();
    error EvidenceAlreadyUsed(bytes32 evidenceId);
    error InvalidCourtOutcome(Outcome outcome);
    error EvidenceBeforeActivation(uint64 evidenceHeight, uint64 validFromHeight);
    error FulfillmentEvidenceLate(uint64 evidenceHeight, uint64 fulfillmentDeadlineHeight);
    error BreachEvidenceAfterProofDeadline(uint64 evidenceHeight, uint64 proofDeadlineHeight);
    error EvidenceHeightNotAttested(uint64 evidenceHeight, uint64 latestAttestedHeight);
    error ProofWindowClosed(uint64 latestAttestedHeight, uint64 proofDeadlineHeight);
    error ProofWindowStillOpen(uint64 latestAttestedHeight, uint64 proofDeadlineHeight);
    error NothingToWithdraw();
    error TransferFailed();
    error Reentrancy();
    error DirectTransferDisabled();

    constructor(address chainInfo) {
        if (chainInfo == address(0)) revert ZeroAddress();
        CHAIN_INFO = IPromiseAttestedHeightSource(chainInfo);
        DEPLOYER = msg.sender;
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

    /// @notice Sets the only evidence court exactly once.
    /// @dev The deployer cannot replace or revoke the court after initialization.
    function initializeCourt(address promiseCourt) external {
        if (msg.sender != DEPLOYER) revert NotDeployer(msg.sender);
        if (court != address(0)) revert CourtAlreadyInitialized(court);
        if (promiseCourt == address(0)) revert ZeroAddress();
        court = promiseCourt;
        emit CourtInitialized(promiseCourt);
    }

    function promiseOf(bytes32 promiseId) external view returns (PromiseRecord memory) {
        return _promises[promiseId];
    }

    /// @notice Opens an immutable promise with an explicit future source-height activation.
    /// @param termsHash Commitment to the kind-specific RFQ or settlement terms interpreted by the court.
    function openPromise(
        PromiseKind kind,
        address beneficiary,
        uint64 sourceChainKey,
        address sourceContract,
        uint64 validFromHeight,
        uint64 fulfillmentDeadlineHeight,
        uint64 proofDeadlineHeight,
        bytes32 termsHash,
        uint256 fixedPenalty
    ) external payable returns (bytes32 promiseId) {
        if (court == address(0)) revert CourtNotInitialized();
        if (beneficiary == address(0) || sourceContract == address(0)) revert ZeroAddress();
        if (termsHash == bytes32(0)) revert ZeroTermsHash();
        if (fixedPenalty == 0) revert ZeroPenalty();
        if (msg.value < fixedPenalty) revert InsufficientBond(msg.value, fixedPenalty);

        _validateHeightWindow(sourceChainKey, validFromHeight, fulfillmentDeadlineHeight, proofDeadlineHeight);

        PromiseTerms memory terms;
        terms.actor = msg.sender;
        terms.beneficiary = beneficiary;
        terms.sourceContract = sourceContract;
        terms.termsHash = termsHash;
        terms.kind = kind;
        terms.sourceChainKey = sourceChainKey;
        terms.validFromHeight = validFromHeight;
        terms.fulfillmentDeadlineHeight = fulfillmentDeadlineHeight;
        terms.proofDeadlineHeight = proofDeadlineHeight;
        terms.fixedPenalty = fixedPenalty;
        terms.bond = msg.value;
        promiseId = _storePromise(terms);
    }

    /// @notice Records a court-authenticated fulfillment or positive breach proof.
    /// @dev The court must derive `evidenceId` from evidence bound to this promise. Evidence IDs are
    ///      consumed globally, preventing one proof from resolving a second promise.
    function resolveWithEvidence(bytes32 promiseId, bytes32 evidenceId, uint64 evidenceHeight, Outcome outcome)
        external
    {
        if (msg.sender != court) revert WrongCourt(msg.sender, court);
        if (outcome != Outcome.FULFILLED && outcome != Outcome.BREACHED) revert InvalidCourtOutcome(outcome);
        if (evidenceId == bytes32(0)) revert ZeroEvidenceId();
        if (usedEvidenceIds[evidenceId]) revert EvidenceAlreadyUsed(evidenceId);

        PromiseRecord storage record = _openPromise(promiseId);
        PromiseTerms storage terms = record.terms;
        if (evidenceHeight < terms.validFromHeight) {
            revert EvidenceBeforeActivation(evidenceHeight, terms.validFromHeight);
        }
        if (outcome == Outcome.FULFILLED && evidenceHeight > terms.fulfillmentDeadlineHeight) {
            revert FulfillmentEvidenceLate(evidenceHeight, terms.fulfillmentDeadlineHeight);
        }
        if (outcome == Outcome.BREACHED && evidenceHeight > terms.proofDeadlineHeight) {
            revert BreachEvidenceAfterProofDeadline(evidenceHeight, terms.proofDeadlineHeight);
        }

        IPromiseAttestedHeightSource.HeightHashResult memory tip = _latestAttested(terms.sourceChainKey);
        if (tip.height > terms.proofDeadlineHeight) {
            revert ProofWindowClosed(tip.height, terms.proofDeadlineHeight);
        }
        if (evidenceHeight > tip.height) revert EvidenceHeightNotAttested(evidenceHeight, tip.height);

        usedEvidenceIds[evidenceId] = true;
        record.outcome = outcome;
        record.evidenceId = evidenceId;
        record.evidenceHeight = evidenceHeight;
        record.resolvedAtAttestedHeight = tip.height;

        (uint256 beneficiaryCredit, uint256 actorCredit) = _creditOutcome(record);
        emit PromiseResolved(promiseId, outcome, evidenceId, evidenceHeight, tip.height, beneficiaryCredit, actorCredit);
    }

    /// @notice Permissionlessly finalizes failure to submit an acceptable proof by the committed deadline.
    /// @dev This proves only the on-book proof-submission default. It does not prove that no fulfillment
    ///      or other source-chain transaction exists.
    function finalizeProofSubmissionDefault(bytes32 promiseId) external {
        PromiseRecord storage record = _openPromise(promiseId);
        PromiseTerms storage terms = record.terms;
        IPromiseAttestedHeightSource.HeightHashResult memory tip = _latestAttested(terms.sourceChainKey);
        if (tip.height <= terms.proofDeadlineHeight) {
            revert ProofWindowStillOpen(tip.height, terms.proofDeadlineHeight);
        }

        record.outcome = Outcome.DEFAULTED;
        record.resolvedAtAttestedHeight = tip.height;
        (uint256 beneficiaryCredit, uint256 actorCredit) = _creditOutcome(record);

        emit ProofSubmissionDefaultFinalized(
            promiseId,
            terms.actor,
            terms.beneficiary,
            terms.proofDeadlineHeight,
            tip.height,
            beneficiaryCredit,
            actorCredit
        );
        emit PromiseResolved(promiseId, Outcome.DEFAULTED, bytes32(0), 0, tip.height, beneficiaryCredit, actorCredit);
    }

    /// @notice Withdraws the caller's accumulated penalty awards or bond refunds.
    function withdrawCredit(address payable recipient) external nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        claimable[msg.sender] = 0;

        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert TransferFailed();
        emit CreditWithdrawn(msg.sender, recipient, amount);
    }

    function _openPromise(bytes32 promiseId) private view returns (PromiseRecord storage record) {
        record = _promises[promiseId];
        if (record.terms.actor == address(0)) revert PromiseNotFound(promiseId);
        if (record.outcome != Outcome.OPEN) revert PromiseAlreadyResolved(promiseId, record.outcome);
    }

    function _validateHeightWindow(
        uint64 sourceChainKey,
        uint64 validFromHeight,
        uint64 fulfillmentDeadlineHeight,
        uint64 proofDeadlineHeight
    ) private view {
        IPromiseAttestedHeightSource.HeightHashResult memory tip = _latestAttested(sourceChainKey);
        if (tip.height > type(uint64).max - MIN_ATTESTED_LEAD_BLOCKS) revert HeightOverflow();

        uint64 minimumHeight = tip.height + MIN_ATTESTED_LEAD_BLOCKS;
        if (validFromHeight < minimumHeight) revert ActivationLeadTooShort(validFromHeight, minimumHeight);
        if (fulfillmentDeadlineHeight < validFromHeight) {
            revert FulfillmentDeadlineBeforeActivation(validFromHeight, fulfillmentDeadlineHeight);
        }
        if (proofDeadlineHeight <= fulfillmentDeadlineHeight) {
            revert ProofDeadlineNotAfterFulfillment(fulfillmentDeadlineHeight, proofDeadlineHeight);
        }
    }

    function _storePromise(PromiseTerms memory terms) private returns (bytes32 promiseId) {
        uint64 nonce = nextNonce[terms.actor]++;
        promiseId = keccak256(abi.encode(block.chainid, address(this), nonce, terms));
        _promises[promiseId].terms = terms;

        ActorStats storage stats = actorStats[terms.actor];
        ++stats.promisesOpened;
        stats.totalBondPosted += terms.bond;

        emit PromiseOpened(
            promiseId,
            terms.kind,
            terms.actor,
            terms.beneficiary,
            terms.sourceChainKey,
            terms.sourceContract,
            terms.validFromHeight,
            terms.fulfillmentDeadlineHeight,
            terms.proofDeadlineHeight,
            terms.termsHash,
            terms.fixedPenalty,
            terms.bond
        );
    }

    function _creditOutcome(PromiseRecord storage record)
        private
        returns (uint256 beneficiaryCredit, uint256 actorCredit)
    {
        PromiseTerms storage terms = record.terms;
        ActorStats storage stats = actorStats[terms.actor];

        if (record.outcome == Outcome.FULFILLED) {
            actorCredit = terms.bond;
            ++stats.promisesFulfilled;
        } else {
            beneficiaryCredit = terms.fixedPenalty;
            actorCredit = terms.bond - terms.fixedPenalty;
            stats.totalPenaltiesCharged += beneficiaryCredit;
            if (record.outcome == Outcome.BREACHED) {
                ++stats.promisesBreached;
            } else {
                ++stats.promisesDefaulted;
            }
        }

        claimable[terms.beneficiary] += beneficiaryCredit;
        claimable[terms.actor] += actorCredit;
    }

    function _latestAttested(uint64 sourceChainKey)
        private
        view
        returns (IPromiseAttestedHeightSource.HeightHashResult memory tip)
    {
        tip = CHAIN_INFO.get_latest_attestation_height_and_hash(sourceChainKey);
        if (!tip.exists || !tip.isAttestation) revert SourceChainNotAttested(sourceChainKey);
    }

    receive() external payable {
        revert DirectTransferDisabled();
    }
}
