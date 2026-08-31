// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PromiseSourceRegistry } from "./PromiseSourceRegistry.sol";

/// @notice Exact subset of Creditcoin's ChainInfo precompile used by PromiseBook.
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

interface IERC1271PromiseBeneficiary {
    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4 magicValue);
}

/// @title PromiseBook
/// @notice Mutually authorized, bonded promises activated with a future Creditcoin block hash.
/// @dev A beneficiary signs every source, policy, timing and economic field before an actor can fund a draft.
///      The final promise ID incorporates a block hash that does not exist at registration, preventing ordinary
///      preparation of favorable source events before the draft. This is backfill resistance, not proof of exact
///      cross-chain wall-clock ordering. DEFAULTED means no acceptable proof reached this book by its deadline.
contract PromiseBook {
    uint64 public constant MIN_ATTESTED_LEAD_BLOCKS = 64;
    uint64 public constant MIN_ENTROPY_DELAY_BLOCKS = 2;
    uint64 public constant MAX_ENTROPY_DELAY_BLOCKS = 64;
    uint64 public constant MIN_ANCHOR_CONFIRMATIONS = 2;
    uint64 public constant BLOCKHASH_RETENTION = 256;

    bytes32 public constant PROMISE_SOURCE_TYPEHASH = keccak256(
        "PromiseSource(address beneficiary,uint8 kind,uint64 sourceChainKey,address sourceContract,bytes32 policyId,uint64 adapterRevision,bytes32 termsHash)"
    );
    bytes32 public constant PROMISE_SCHEDULE_TYPEHASH = keccak256(
        "PromiseSchedule(uint64 activationLeadBlocks,uint64 fulfillmentWindowBlocks,uint64 proofSubmissionWindowBlocks,uint64 entropyBlock,uint64 activationDeadlineBlock,uint256 fixedPenalty,uint256 bond,uint256 beneficiaryNonce)"
    );
    bytes32 public constant PROMISE_DRAFT_TYPEHASH = keccak256(
        "PromiseDraft(address actor,PromiseSource source,PromiseSchedule schedule)PromiseSchedule(uint64 activationLeadBlocks,uint64 fulfillmentWindowBlocks,uint64 proofSubmissionWindowBlocks,uint64 entropyBlock,uint64 activationDeadlineBlock,uint256 fixedPenalty,uint256 bond,uint256 beneficiaryNonce)PromiseSource(address beneficiary,uint8 kind,uint64 sourceChainKey,address sourceContract,bytes32 policyId,uint64 adapterRevision,bytes32 termsHash)"
    );

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("PROVER PromiseBook");
    bytes32 private constant VERSION_HASH = keccak256("2");
    bytes32 private constant DRAFT_ID_DOMAIN = keccak256("PROVER_PROMISE_DRAFT_ID_V1");
    bytes32 private constant PROMISE_ID_DOMAIN = keccak256("PROVER_PROMISE_ID_V2");
    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;
    uint256 private constant SECP256K1_HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    uint256 private constant EIP2098_S_MASK = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

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

    enum DraftStatus {
        NONE,
        PENDING,
        ACTIVATED,
        EXPIRED
    }

    enum DraftExpiryReason {
        ACTIVATION_WINDOW_CLOSED,
        SOURCE_POLICY_CHANGED
    }

    struct DraftParams {
        PromiseKind kind;
        address beneficiary;
        uint64 sourceChainKey;
        address sourceContract;
        bytes32 policyId;
        uint64 adapterRevision;
        bytes32 termsHash;
        uint64 activationLeadBlocks;
        uint64 fulfillmentWindowBlocks;
        uint64 proofSubmissionWindowBlocks;
        uint64 entropyBlock;
        uint64 activationDeadlineBlock;
        uint256 fixedPenalty;
        uint256 bond;
        uint256 beneficiaryNonce;
    }

    struct DraftRecord {
        address actor;
        DraftParams params;
        DraftStatus status;
        bytes32 authorizationDigest;
        bytes32 sourceKey;
        bytes32 promiseId;
    }

    struct PromiseTerms {
        address actor;
        address beneficiary;
        address sourceContract;
        bytes32 termsHash;
        bytes32 policyId;
        PromiseKind kind;
        uint64 sourceChainKey;
        uint64 sourcePolicyRevision;
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
        bytes32 draftId;
        bytes32 entropyHash;
        uint64 activationAttestedHeight;
        bytes32 activationAttestationHash;
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
    PromiseSourceRegistry public immutable SOURCE_REGISTRY;
    address public immutable DEPLOYER;
    address public court;

    mapping(address actor => uint64 nonce) public nextDraftNonce;
    mapping(address beneficiary => mapping(uint256 word => uint256 bitmap)) private _beneficiaryNonceBitmap;
    mapping(address actor => ActorStats stats) public actorStats;
    mapping(bytes32 evidenceId => bool used) public usedEvidenceIds;
    mapping(address account => uint256 amount) public claimable;
    mapping(bytes32 draftId => DraftRecord record) private _drafts;
    mapping(bytes32 promiseId => PromiseRecord record) private _promises;

    uint256 private _entered;

    event CourtInitialized(address indexed court);
    event BeneficiaryNoncesInvalidated(address indexed beneficiary, uint256 indexed word, uint256 mask);
    event PromiseDraftRegistered(
        bytes32 indexed draftId,
        address indexed actor,
        address indexed beneficiary,
        bytes32 sourceKey,
        uint64 adapterRevision,
        uint64 entropyBlock,
        uint64 activationDeadlineBlock,
        bytes32 authorizationDigest,
        uint256 bond
    );
    event PromiseDraftActivated(
        bytes32 indexed draftId,
        bytes32 indexed promiseId,
        bytes32 indexed entropyHash,
        uint64 activationAttestedHeight,
        bytes32 activationAttestationHash,
        uint64 validFromHeight,
        uint64 fulfillmentDeadlineHeight,
        uint64 proofDeadlineHeight
    );
    event PromiseDraftExpired(
        bytes32 indexed draftId, address indexed actor, DraftExpiryReason indexed reason, uint256 refund
    );
    event PromiseOpened(
        bytes32 indexed promiseId,
        PromiseKind indexed kind,
        address indexed actor,
        address beneficiary,
        uint64 sourceChainKey,
        address sourceContract,
        bytes32 policyId,
        uint64 sourcePolicyRevision,
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
    error ActorIsBeneficiary(address actor);
    error ZeroTermsHash();
    error ZeroPolicyId();
    error ZeroPenalty();
    error IncorrectBond(uint256 supplied, uint256 authorized);
    error PenaltyExceedsBond(uint256 penalty, uint256 bond);
    error SourceChainNotAttested(uint64 sourceChainKey);
    error HeightOverflow();
    error ActivationLeadTooShort(uint64 requestedLead, uint64 minimumLead);
    error ZeroFulfillmentWindow();
    error ZeroProofSubmissionWindow();
    error EntropyBlockNotFuture(uint64 requested, uint256 minimum);
    error EntropyBlockTooFar(uint64 requested, uint256 maximum);
    error InvalidActivationDeadline(uint64 entropyBlock, uint64 activationDeadlineBlock);
    error NotDeployer(address caller);
    error CourtAlreadyInitialized(address court);
    error CourtNotInitialized();
    error SourceNotApproved(bytes32 sourceKey);
    error SourceRevisionMismatch(bytes32 sourceKey, uint64 expected, uint64 actual);
    error BeneficiaryNonceAlreadyUsed(address beneficiary, uint256 nonce);
    error InvalidBeneficiarySignature(address beneficiary);
    error InvalidSignatureLength(uint256 length);
    error InvalidSignatureS(bytes32 s);
    error InvalidSignatureV(uint8 v);
    error DraftNotFound(bytes32 draftId);
    error DraftNotPending(bytes32 draftId, DraftStatus status);
    error ActivationTooEarly(uint256 current, uint256 earliest);
    error ActivationWindowClosed(uint256 current, uint64 deadline);
    error EntropyHashUnavailable(uint64 entropyBlock);
    error DraftNotExpirable(bytes32 draftId);
    error PromiseIdCollision(bytes32 promiseId);
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

    constructor(address chainInfo, address sourceRegistry) {
        if (chainInfo == address(0) || sourceRegistry == address(0)) revert ZeroAddress();
        CHAIN_INFO = IPromiseAttestedHeightSource(chainInfo);
        SOURCE_REGISTRY = PromiseSourceRegistry(sourceRegistry);
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

    function initializeCourt(address promiseCourt) external {
        if (msg.sender != DEPLOYER) revert NotDeployer(msg.sender);
        if (court != address(0)) revert CourtAlreadyInitialized(court);
        if (promiseCourt == address(0)) revert ZeroAddress();
        court = promiseCourt;
        emit CourtInitialized(promiseCourt);
    }

    // EIP-712's conventional introspection name is intentionally uppercase.
    // forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function draftOf(bytes32 draftId) external view returns (DraftRecord memory) {
        return _drafts[draftId];
    }

    function promiseOf(bytes32 promiseId) external view returns (PromiseRecord memory) {
        return _promises[promiseId];
    }

    function beneficiaryNonceUsed(address beneficiary, uint256 nonce) public view returns (bool) {
        (uint256 word, uint256 mask) = _noncePosition(nonce);
        return _beneficiaryNonceBitmap[beneficiary][word] & mask != 0;
    }

    function invalidateBeneficiaryNonces(uint256 word, uint256 mask) external {
        _beneficiaryNonceBitmap[msg.sender][word] |= mask;
        emit BeneficiaryNoncesInvalidated(msg.sender, word, mask);
    }

    function draftAuthorizationDigest(address actor, DraftParams calldata params) public view returns (bytes32) {
        bytes32 structHash = _draftStructHash(actor, params);
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
    }

    /// @notice Registers a funded proposal after exact EIP-712 authorization by its beneficiary.
    function registerDraft(DraftParams calldata params, bytes calldata beneficiarySignature)
        external
        payable
        returns (bytes32 draftId)
    {
        if (court == address(0)) revert CourtNotInitialized();
        _validateDraftParams(msg.sender, params, msg.value);
        if (beneficiaryNonceUsed(params.beneficiary, params.beneficiaryNonce)) {
            revert BeneficiaryNonceAlreadyUsed(params.beneficiary, params.beneficiaryNonce);
        }

        (bytes32 key, PromiseSourceRegistry.Approval memory approval) = SOURCE_REGISTRY.approvalOf(
            uint8(params.kind), params.sourceChainKey, params.sourceContract, params.policyId
        );
        if (!approval.approved) revert SourceNotApproved(key);
        if (approval.revision != params.adapterRevision) {
            revert SourceRevisionMismatch(key, params.adapterRevision, approval.revision);
        }

        _latestAttested(params.sourceChainKey);
        bytes32 authorizationDigest = draftAuthorizationDigest(msg.sender, params);
        _validateBeneficiarySignature(params.beneficiary, authorizationDigest, beneficiarySignature);

        _consumeBeneficiaryNonce(params.beneficiary, params.beneficiaryNonce);
        uint64 draftNonce = nextDraftNonce[msg.sender]++;
        draftId = keccak256(
            abi.encode(DRAFT_ID_DOMAIN, block.chainid, address(this), msg.sender, draftNonce, authorizationDigest)
        );

        DraftRecord storage draft = _drafts[draftId];
        draft.actor = msg.sender;
        draft.params = params;
        draft.status = DraftStatus.PENDING;
        draft.authorizationDigest = authorizationDigest;
        draft.sourceKey = key;

        _emitDraftRegistered(draftId, draft);
    }

    /// @notice Permissionlessly activates a draft after its signed future block hash becomes available.
    function activateDraft(bytes32 draftId) external returns (bytes32 promiseId) {
        DraftRecord storage draft = _pendingDraft(draftId);
        DraftParams storage params = draft.params;

        uint256 earliest = uint256(params.entropyBlock) + MIN_ANCHOR_CONFIRMATIONS;
        if (block.number < earliest) revert ActivationTooEarly(block.number, earliest);
        if (block.number > params.activationDeadlineBlock) {
            revert ActivationWindowClosed(block.number, params.activationDeadlineBlock);
        }
        if (block.number - uint256(params.entropyBlock) > BLOCKHASH_RETENTION) {
            revert EntropyHashUnavailable(params.entropyBlock);
        }

        bytes32 entropyHash = blockhash(params.entropyBlock);
        if (entropyHash == bytes32(0)) revert EntropyHashUnavailable(params.entropyBlock);
        _requireCurrentApproval(draft);

        IPromiseAttestedHeightSource.HeightHashResult memory tip = _latestAttested(params.sourceChainKey);
        (uint64 validFrom, uint64 fulfillmentDeadline, uint64 proofDeadline) = _deriveHeights(params, tip.height);
        promiseId = keccak256(
            abi.encode(
                PROMISE_ID_DOMAIN,
                block.chainid,
                address(this),
                draftId,
                params.entropyBlock,
                entropyHash,
                tip.height,
                tip.hash,
                validFrom,
                fulfillmentDeadline,
                proofDeadline
            )
        );
        if (_promises[promiseId].terms.actor != address(0)) revert PromiseIdCollision(promiseId);

        PromiseTerms memory terms = PromiseTerms({
            actor: draft.actor,
            beneficiary: params.beneficiary,
            sourceContract: params.sourceContract,
            termsHash: params.termsHash,
            policyId: params.policyId,
            kind: params.kind,
            sourceChainKey: params.sourceChainKey,
            sourcePolicyRevision: params.adapterRevision,
            validFromHeight: validFrom,
            fulfillmentDeadlineHeight: fulfillmentDeadline,
            proofDeadlineHeight: proofDeadline,
            fixedPenalty: params.fixedPenalty,
            bond: params.bond
        });

        PromiseRecord storage record = _promises[promiseId];
        record.terms = terms;
        record.draftId = draftId;
        record.entropyHash = entropyHash;
        record.activationAttestedHeight = tip.height;
        record.activationAttestationHash = tip.hash;
        draft.status = DraftStatus.ACTIVATED;
        draft.promiseId = promiseId;

        ActorStats storage stats = actorStats[draft.actor];
        ++stats.promisesOpened;
        stats.totalBondPosted += params.bond;

        _emitDraftActivated(draftId, promiseId, record);
        _emitPromiseOpened(promiseId, record.terms);
    }

    function _emitDraftActivated(bytes32 draftId, bytes32 promiseId, PromiseRecord storage record) private {
        emit PromiseDraftActivated(
            draftId,
            promiseId,
            record.entropyHash,
            record.activationAttestedHeight,
            record.activationAttestationHash,
            record.terms.validFromHeight,
            record.terms.fulfillmentDeadlineHeight,
            record.terms.proofDeadlineHeight
        );
    }

    function _emitPromiseOpened(bytes32 promiseId, PromiseTerms storage terms) private {
        emit PromiseOpened(
            promiseId,
            terms.kind,
            terms.actor,
            terms.beneficiary,
            terms.sourceChainKey,
            terms.sourceContract,
            terms.policyId,
            terms.sourcePolicyRevision,
            terms.validFromHeight,
            terms.fulfillmentDeadlineHeight,
            terms.proofDeadlineHeight,
            terms.termsHash,
            terms.fixedPenalty,
            terms.bond
        );
    }

    /// @notice Neutrally unwinds a draft after its activation window or source approval becomes invalid.
    function expireDraft(bytes32 draftId) external {
        DraftRecord storage draft = _pendingDraft(draftId);
        DraftExpiryReason reason;
        if (!_hasCurrentApproval(draft)) {
            reason = DraftExpiryReason.SOURCE_POLICY_CHANGED;
        } else if (block.number > draft.params.activationDeadlineBlock) {
            reason = DraftExpiryReason.ACTIVATION_WINDOW_CLOSED;
        } else {
            revert DraftNotExpirable(draftId);
        }

        draft.status = DraftStatus.EXPIRED;
        claimable[draft.actor] += draft.params.bond;
        emit PromiseDraftExpired(draftId, draft.actor, reason, draft.params.bond);
    }

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

    /// @notice Finalizes only failure to submit acceptable evidence by the committed proof deadline.
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

    function withdrawCredit(address payable recipient) external nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        claimable[msg.sender] = 0;

        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert TransferFailed();
        emit CreditWithdrawn(msg.sender, recipient, amount);
    }

    function _validateDraftParams(address actor, DraftParams calldata params, uint256 suppliedBond) private view {
        if (params.beneficiary == address(0) || params.sourceContract == address(0)) revert ZeroAddress();
        if (actor == params.beneficiary) revert ActorIsBeneficiary(actor);
        if (params.termsHash == bytes32(0)) revert ZeroTermsHash();
        if (params.policyId == bytes32(0)) revert ZeroPolicyId();
        if (params.fixedPenalty == 0) revert ZeroPenalty();
        if (suppliedBond != params.bond) revert IncorrectBond(suppliedBond, params.bond);
        if (params.fixedPenalty > params.bond) revert PenaltyExceedsBond(params.fixedPenalty, params.bond);
        if (params.activationLeadBlocks < MIN_ATTESTED_LEAD_BLOCKS) {
            revert ActivationLeadTooShort(params.activationLeadBlocks, MIN_ATTESTED_LEAD_BLOCKS);
        }
        if (params.fulfillmentWindowBlocks == 0) revert ZeroFulfillmentWindow();
        if (params.proofSubmissionWindowBlocks == 0) revert ZeroProofSubmissionWindow();
        if (block.number > type(uint64).max - MAX_ENTROPY_DELAY_BLOCKS) revert HeightOverflow();

        uint256 minimumEntropy = block.number + MIN_ENTROPY_DELAY_BLOCKS;
        uint256 maximumEntropy = block.number + MAX_ENTROPY_DELAY_BLOCKS;
        if (params.entropyBlock < minimumEntropy) {
            revert EntropyBlockNotFuture(params.entropyBlock, minimumEntropy);
        }
        if (params.entropyBlock > maximumEntropy) {
            revert EntropyBlockTooFar(params.entropyBlock, maximumEntropy);
        }
        if (
            uint256(params.entropyBlock) + MIN_ANCHOR_CONFIRMATIONS > params.activationDeadlineBlock
                || uint256(params.entropyBlock) + BLOCKHASH_RETENTION < params.activationDeadlineBlock
        ) {
            revert InvalidActivationDeadline(params.entropyBlock, params.activationDeadlineBlock);
        }
    }

    function _emitDraftRegistered(bytes32 draftId, DraftRecord storage draft) private {
        emit PromiseDraftRegistered(
            draftId,
            draft.actor,
            draft.params.beneficiary,
            draft.sourceKey,
            draft.params.adapterRevision,
            draft.params.entropyBlock,
            draft.params.activationDeadlineBlock,
            draft.authorizationDigest,
            draft.params.bond
        );
    }

    function _draftStructHash(address actor, DraftParams calldata params) private pure returns (bytes32) {
        bytes32 sourceHash = keccak256(
            abi.encode(
                PROMISE_SOURCE_TYPEHASH,
                params.beneficiary,
                uint8(params.kind),
                params.sourceChainKey,
                params.sourceContract,
                params.policyId,
                params.adapterRevision,
                params.termsHash
            )
        );
        bytes32 scheduleHash = keccak256(
            abi.encode(
                PROMISE_SCHEDULE_TYPEHASH,
                params.activationLeadBlocks,
                params.fulfillmentWindowBlocks,
                params.proofSubmissionWindowBlocks,
                params.entropyBlock,
                params.activationDeadlineBlock,
                params.fixedPenalty,
                params.bond,
                params.beneficiaryNonce
            )
        );
        return keccak256(abi.encode(PROMISE_DRAFT_TYPEHASH, actor, sourceHash, scheduleHash));
    }

    function _validateBeneficiarySignature(address beneficiary, bytes32 digest, bytes calldata signature) private view {
        if (beneficiary.code.length != 0) {
            (bool success, bytes memory result) = beneficiary.staticcall(
                abi.encodeCall(IERC1271PromiseBeneficiary.isValidSignature, (digest, signature))
            );
            if (!success || result.length != 32 || abi.decode(result, (bytes4)) != EIP1271_MAGIC_VALUE) {
                revert InvalidBeneficiarySignature(beneficiary);
            }
            return;
        }

        (bytes32 r, bytes32 s, uint8 v) = _decodeEoaSignature(signature);
        if (uint256(s) == 0 || uint256(s) > SECP256K1_HALF_ORDER) revert InvalidSignatureS(s);
        if (v != 27 && v != 28) revert InvalidSignatureV(v);
        if (ecrecover(digest, v, r, s) != beneficiary) revert InvalidBeneficiarySignature(beneficiary);
    }

    function _decodeEoaSignature(bytes calldata signature) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (signature.length == 65) {
            assembly ("memory-safe") {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 0x20))
                v := byte(0, calldataload(add(signature.offset, 0x40)))
            }
        } else if (signature.length == 64) {
            bytes32 vs;
            assembly ("memory-safe") {
                r := calldataload(signature.offset)
                vs := calldataload(add(signature.offset, 0x20))
            }
            s = bytes32(uint256(vs) & EIP2098_S_MASK);
            v = uint8((uint256(vs) >> 255) + 27);
        } else {
            revert InvalidSignatureLength(signature.length);
        }
    }

    function _consumeBeneficiaryNonce(address beneficiary, uint256 nonce) private {
        (uint256 word, uint256 mask) = _noncePosition(nonce);
        _beneficiaryNonceBitmap[beneficiary][word] |= mask;
    }

    function _noncePosition(uint256 nonce) private pure returns (uint256 word, uint256 mask) {
        word = nonce >> 8;
        mask = uint256(1) << (nonce & 255);
    }

    function _pendingDraft(bytes32 draftId) private view returns (DraftRecord storage draft) {
        draft = _drafts[draftId];
        if (draft.actor == address(0)) revert DraftNotFound(draftId);
        if (draft.status != DraftStatus.PENDING) revert DraftNotPending(draftId, draft.status);
    }

    function _requireCurrentApproval(DraftRecord storage draft) private view {
        (, PromiseSourceRegistry.Approval memory approval) = SOURCE_REGISTRY.approvalOf(
            uint8(draft.params.kind), draft.params.sourceChainKey, draft.params.sourceContract, draft.params.policyId
        );
        if (!approval.approved) revert SourceNotApproved(draft.sourceKey);
        if (approval.revision != draft.params.adapterRevision) {
            revert SourceRevisionMismatch(draft.sourceKey, draft.params.adapterRevision, approval.revision);
        }
    }

    function _hasCurrentApproval(DraftRecord storage draft) private view returns (bool) {
        (, PromiseSourceRegistry.Approval memory approval) = SOURCE_REGISTRY.approvalOf(
            uint8(draft.params.kind), draft.params.sourceChainKey, draft.params.sourceContract, draft.params.policyId
        );
        return approval.approved && approval.revision == draft.params.adapterRevision;
    }

    function _deriveHeights(DraftParams storage params, uint64 attestedHeight)
        private
        view
        returns (uint64 validFrom, uint64 fulfillmentDeadline, uint64 proofDeadline)
    {
        if (attestedHeight > type(uint64).max - params.activationLeadBlocks) revert HeightOverflow();
        validFrom = attestedHeight + params.activationLeadBlocks;
        uint64 fulfillmentOffset = params.fulfillmentWindowBlocks - 1;
        if (validFrom > type(uint64).max - fulfillmentOffset) revert HeightOverflow();
        fulfillmentDeadline = validFrom + fulfillmentOffset;
        if (fulfillmentDeadline > type(uint64).max - params.proofSubmissionWindowBlocks) revert HeightOverflow();
        proofDeadline = fulfillmentDeadline + params.proofSubmissionWindowBlocks;
    }

    function _openPromise(bytes32 promiseId) private view returns (PromiseRecord storage record) {
        record = _promises[promiseId];
        if (record.terms.actor == address(0)) revert PromiseNotFound(promiseId);
        if (record.outcome != Outcome.OPEN) revert PromiseAlreadyResolved(promiseId, record.outcome);
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
