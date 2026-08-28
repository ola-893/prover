// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CovenantBook } from "./CovenantBook.sol";
import { PerformanceBureau } from "./PerformanceBureau.sol";
import { AttestcoinProofAdapter } from "./attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "./attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";
import { OrderingPredicates } from "./attestcoin/OrderingPredicates.sol";

/// @title OrderingCourt
/// @notice Settles relay-authorized no-sandwich outcome warranties and FIFO covenants from
///         Attestcoin-authenticated transaction history.
/// @dev The court never accepts decoded facts as caller inputs. It first verifies the exact V1
///      `(transaction, receipt)` bytes, then derives senders, recipients, successful execution,
///      logs and transaction positions from those same authenticated bytes. A sandwich ruling
///      proves the policy-bound signer authorized liability for the victim route; it does not
///      prove who sent either surrounding transaction or personally executed the pattern.
contract OrderingCourt is AttestcoinProofAdapter {
    bytes32 public constant UNISWAP_V2_SWAP = keccak256("Swap(address,uint256,uint256,uint256,uint256,address)");
    bytes32 public constant EXIT_REQUESTED = keccak256("ExitRequested(uint256,address,uint256)");
    bytes32 public constant EXIT_PROCESSED = keccak256("ExitProcessed(uint256,address,uint256)");

    uint256 private constant SWAP_DATA_LENGTH = 128;
    uint256 private constant EXIT_DATA_LENGTH = 32;
    uint256 private constant EXPECTED_SWAP_TOPICS = 3;
    uint256 private constant EXPECTED_EXIT_TOPICS = 3;
    uint256 private constant ECDSA_SIGNATURE_LENGTH = 65;
    uint256 private constant SECP256K1_HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    enum RulingKind {
        SANDWICH,
        FIFO_INVERSION
    }

    /// @notice One independently provable source transaction, used by the cross-block FIFO path.
    struct SourceTransactionProof {
        BlockContext context;
        TransactionInclusion inclusion;
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

    /// @notice An EOA authorization from the signer fixed by the covenant's policy hash.
    struct RelayRouteAuthorization {
        uint64 validUntilHeight;
        bytes signature;
    }

    struct DecodedEvmTransaction {
        address from;
        address to;
        uint64 nonce;
        uint256 value;
        bytes32 callDataHash;
        EvmV1Decoder.ReceiptFields receipt;
    }

    struct SwapAmounts {
        uint256 amount0In;
        uint256 amount1In;
        uint256 amount0Out;
        uint256 amount1Out;
    }

    struct DirectedFlow {
        uint256 numeraireIn;
        uint256 numeraireOut;
        uint256 counterIn;
        uint256 counterOut;
    }

    struct ExitFact {
        uint256 requestId;
        address owner;
        uint256 amount;
    }

    struct SandwichFacts {
        bytes32 frontEvidenceId;
        bytes32 victimEvidenceId;
        bytes32 backEvidenceId;
        address affectedUser;
        address victimTo;
        uint64 victimNonce;
        uint256 victimValue;
        bytes32 victimCallDataHash;
    }

    struct FifoFacts {
        bytes32 requestAEvidenceId;
        bytes32 requestBEvidenceId;
        bytes32 processBEvidenceId;
        bytes32 processAEvidenceId;
        uint256 requestAId;
        uint256 requestBId;
        uint64 breachHeight;
        address beneficiary;
    }

    CovenantBook public immutable COVENANT_BOOK;
    PerformanceBureau public immutable PERFORMANCE_BUREAU;

    mapping(bytes32 rulingId => Ruling ruling) private _rulings;
    bytes32[] private _rulingIds;
    uint256 private _entered;

    event OrderingBreachRuled(
        bytes32 indexed rulingId,
        bytes32 indexed covenantId,
        RulingKind indexed kind,
        address operator,
        address affectedUser,
        address beneficiary,
        uint64 breachHeight,
        uint256 paid,
        uint256 shortfall
    );
    event RelayRouteAuthorizationVerified(
        bytes32 indexed covenantId,
        bytes32 indexed authorizationDigest,
        address indexed authorizationSigner,
        uint64 validUntilHeight
    );
    event BureauEvidenceRecorded(bytes32 indexed rulingId);
    event BureauEvidenceDeferred(bytes32 indexed rulingId, bytes32 indexed revertDataHash);

    error ZeroAddress();
    error WrongProofCount(uint256 expected, uint256 actual);
    error CovenantNotFound(bytes32 covenantId);
    error WrongCovenantType(CovenantBook.CovenantType expected, CovenantBook.CovenantType actual);
    error WrongSourceChain(uint256 proof, uint64 expected, uint64 actual);
    error ProofOutsideCoverage(uint256 proof, uint64 height, uint64 validFromHeight, uint64 validUntilHeight);
    error PenaltyDoesNotFitBureauValue(uint256 fixedPenalty);
    error UnsupportedTransactionType(uint256 proof, uint8 txType);
    error SourceTransactionReverted(uint256 proof);
    error ExpectedEventMissing(uint256 proof, address emitter, bytes32 eventSignature);
    error ExpectedEventAmbiguous(uint256 proof, address emitter, bytes32 eventSignature, uint256 count);
    error MalformedEvent(uint256 proof, uint256 topicCount, uint256 dataLength);
    error SearcherMismatch(address frontSender, address backSender);
    error VictimIsSearcher(address searcher);
    error VictimEntrypointMismatch(address expected, address actual);
    error SandwichPolicyMismatch(bytes32 committedPolicyHash, bytes32 requiredPolicyHash);
    error FifoPolicyMismatch(bytes32 committedPolicyHash, bytes32 requiredPolicyHash);
    error AuthorizationExpired(uint64 victimHeight, uint64 validUntilHeight);
    error AuthorizationExceedsCoverage(uint64 validUntilHeight, uint64 covenantValidUntilHeight);
    error InvalidAuthorizationSignatureLength(uint256 actual);
    error InvalidAuthorizationS(bytes32 s);
    error InvalidAuthorizationV(uint8 v);
    error InvalidAuthorizationSigner(address expected, address actual);
    error SandwichLegsNotAdjacent(uint64 frontIndex, uint64 victimIndex, uint64 backIndex);
    error CounterAssetNotConserved(uint256 acquired, uint256 sold);
    error InvalidSwapDirection(uint256 proof);
    error NoGrossPositiveCycle(uint256 spent, uint256 recovered);
    error RequestIdsNotAscending(uint256 requestA, uint256 requestB);
    error ProcessSenderMismatch(uint256 processProof, address expectedSigner, address actualSender);
    error ProcessedRequestMismatch(uint256 processProof, uint256 expectedRequestId, uint256 actualRequestId);
    error ProcessedOwnerMismatch(uint256 processProof, address expectedOwner, address actualOwner);
    error MalformedIndexedAddress(uint256 proof, bytes32 topic);
    error RulingAlreadyExists(bytes32 rulingId);
    error RulingNotFound(bytes32 rulingId);
    error Reentrancy();

    constructor(INativeQueryVerifier verifier_, CovenantBook covenantBook_, PerformanceBureau performanceBureau_)
        AttestcoinProofAdapter(verifier_)
    {
        if (address(covenantBook_) == address(0) || address(performanceBureau_) == address(0)) revert ZeroAddress();
        COVENANT_BOOK = covenantBook_;
        PERFORMANCE_BUREAU = performanceBureau_;
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

    function rulingOf(bytes32 rulingId) external view returns (Ruling memory) {
        return _rulings[rulingId];
    }

    function rulingCount() external view returns (uint256) {
        return _rulingIds.length;
    }

    function rulingAt(uint256 index) external view returns (bytes32 rulingId, Ruling memory ruling) {
        rulingId = _rulingIds[index];
        ruling = _rulings[rulingId];
    }

    /// @notice Proves a three-transaction outcome against an operator-authorized victim route and
    ///         settles the relay's no-sandwich outcome warranty.
    /// @param pool Exact AMM pool that must have emitted one qualifying Swap in every transaction.
    /// @param numeraireIsToken0 Orientation used for the buy/same-direction/sell checks.
    function proveSandwich(
        bytes32 covenantId,
        BlockContext calldata context,
        TransactionInclusion[] calldata inclusions,
        address pool,
        bool numeraireIsToken0,
        address recoveryPool,
        address authorizationSigner,
        RelayRouteAuthorization calldata authorization
    ) external nonReentrant returns (bytes32 rulingId) {
        if (pool == address(0) || recoveryPool == address(0) || authorizationSigner == address(0)) {
            revert ZeroAddress();
        }
        if (inclusions.length != 3) revert WrongProofCount(3, inclusions.length);

        CovenantBook.Covenant memory covenant = _loadCovenant(covenantId, CovenantBook.CovenantType.NO_SANDWICH);
        _assertCovered(covenant, context.chainKey, context.blockHeight, 0);
        bytes32 requiredPolicyHash =
            sandwichPolicyHash(covenant.sourceContract, pool, numeraireIsToken0, recoveryPool, authorizationSigner);
        if (covenant.policyHash != requiredPolicyHash) {
            revert SandwichPolicyMismatch(covenant.policyHash, requiredPolicyHash);
        }

        SandwichFacts memory facts = _verifySandwich(covenant, context, inclusions, pool, numeraireIsToken0);
        _verifyRelayRouteAuthorization(
            covenantId, covenant, context.blockHeight, facts, authorizationSigner, authorization
        );

        return _settleSandwich(covenantId, covenant, context.blockHeight, facts, recoveryPool);
    }

    /// @notice Deterministic policy commitment used when opening a no-sandwich covenant.
    function sandwichPolicyHash(
        address entrypoint,
        address pool,
        bool numeraireIsToken0,
        address recoveryPool,
        address authorizationSigner
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "ORDERING_COURT_NO_SANDWICH_POLICY_V3",
                entrypoint,
                pool,
                numeraireIsToken0,
                recoveryPool,
                authorizationSigner
            )
        );
    }

    /// @notice EIP-191 liability authorization for one exact source-chain route.
    function sandwichAuthorizationDigest(
        bytes32 covenantId,
        uint64 chainKey,
        address victim,
        uint64 victimNonce,
        address victimTo,
        uint256 victimValue,
        bytes32 victimCallDataHash,
        uint64 validUntilHeight
    ) public view returns (bytes32 digest) {
        bytes32 authorizationHash = keccak256(
            abi.encode(
                "ORDERING_COURT_ROUTE_AUTHORIZATION_V2",
                block.chainid,
                address(this),
                covenantId,
                chainKey,
                victim,
                victimNonce,
                victimTo,
                victimValue,
                victimCallDataHash,
                validUntilHeight
            )
        );
        digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", authorizationHash));
    }

    /// @notice Proves that a later exit request was processed before an earlier one.
    /// @dev Proof roles are fixed: `[request A, request B, process B, process A]`. Each transaction
    ///      carries its own continuity proof, so requests and processing may span source blocks.
    function proveFifoInversion(bytes32 covenantId, SourceTransactionProof[] calldata proofs, address processingSigner)
        external
        nonReentrant
        returns (bytes32 rulingId)
    {
        if (processingSigner == address(0)) revert ZeroAddress();
        if (proofs.length != 4) revert WrongProofCount(4, proofs.length);
        CovenantBook.Covenant memory covenant = _loadCovenant(covenantId, CovenantBook.CovenantType.FIFO);
        bytes32 requiredPolicyHash = fifoPolicyHash(covenant.sourceContract, processingSigner);
        if (covenant.policyHash != requiredPolicyHash) {
            revert FifoPolicyMismatch(covenant.policyHash, requiredPolicyHash);
        }

        FifoFacts memory facts = _verifyFifo(covenant, proofs, processingSigner);

        rulingId = keccak256(
            abi.encode(
                "ORDERING_COURT_FIFO_V1",
                covenantId,
                facts.requestAEvidenceId,
                facts.requestBEvidenceId,
                facts.processBEvidenceId,
                facts.processAEvidenceId,
                facts.requestAId,
                facts.requestBId
            )
        );
        _settle(
            rulingId,
            covenantId,
            covenant,
            RulingKind.FIFO_INVERSION,
            facts.breachHeight,
            facts.beneficiary,
            facts.beneficiary
        );
    }

    /// @notice Commits the FIFO warranty to a processing signer, unique non-cancellable request
    ///         IDs, and this court's exact event schema. The source vault must enforce the policy.
    function fifoPolicyHash(address vault, address processingSigner) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "ORDERING_COURT_FIFO_POLICY_V2",
                vault,
                processingSigner,
                EXIT_REQUESTED,
                EXIT_PROCESSED,
                "UNIQUE_NONCANCELLABLE_REQUEST_IDS"
            )
        );
    }

    /// @notice Retries a profile write without putting an already-settled bond award at risk.
    function syncRulingToBureau(bytes32 rulingId) external nonReentrant returns (bool recorded) {
        Ruling storage ruling = _rulings[rulingId];
        if (ruling.covenantId == bytes32(0)) revert RulingNotFound(rulingId);
        if (ruling.bureauRecorded) return true;
        return _tryRecordBureauEvidence(rulingId, ruling);
    }

    function _verifySandwich(
        CovenantBook.Covenant memory covenant,
        BlockContext calldata context,
        TransactionInclusion[] calldata inclusions,
        address pool,
        bool numeraireIsToken0
    ) private returns (SandwichFacts memory facts) {
        VerifiedTransaction[] memory proven = _verifySameBlockBatch(context, inclusions);
        DecodedEvmTransaction[] memory decoded = new DecodedEvmTransaction[](3);
        SwapAmounts[] memory swaps = new SwapAmounts[](3);
        OrderingPredicates.Position[] memory positions = new OrderingPredicates.Position[](3);

        for (uint256 i; i < 3; ++i) {
            decoded[i] = _decodeSuccessful(inclusions[i].encodedTransaction, i);
            swaps[i] = _exactEventSwap(decoded[i].receipt, pool, i);
            positions[i] = proven[i].position;
        }
        if (
            !OrderingPredicates.isImmediatelyBeforeInBlock(positions[0], positions[1])
                || !OrderingPredicates.isImmediatelyBeforeInBlock(positions[1], positions[2])
        ) {
            revert SandwichLegsNotAdjacent(positions[0].txIndex, positions[1].txIndex, positions[2].txIndex);
        }

        if (decoded[0].from != decoded[2].from) revert SearcherMismatch(decoded[0].from, decoded[2].from);
        if (decoded[1].from == decoded[0].from) revert VictimIsSearcher(decoded[0].from);
        if (decoded[1].to != covenant.sourceContract) {
            revert VictimEntrypointMismatch(covenant.sourceContract, decoded[1].to);
        }

        _assertSandwichFlows(swaps, numeraireIsToken0);

        facts.frontEvidenceId = proven[0].evidenceId;
        facts.victimEvidenceId = proven[1].evidenceId;
        facts.backEvidenceId = proven[2].evidenceId;
        facts.affectedUser = decoded[1].from;
        facts.victimTo = decoded[1].to;
        facts.victimNonce = decoded[1].nonce;
        facts.victimValue = decoded[1].value;
        facts.victimCallDataHash = decoded[1].callDataHash;
    }

    function _settleSandwich(
        bytes32 covenantId,
        CovenantBook.Covenant memory covenant,
        uint64 breachHeight,
        SandwichFacts memory facts,
        address recoveryPool
    ) private returns (bytes32 rulingId) {
        // Caller-selected interpretation parameters are intentionally excluded: one authenticated
        // transaction triplet can settle this covenant only once, even if it traversed many pools.
        rulingId = keccak256(
            abi.encode(
                "ORDERING_COURT_SANDWICH_V1",
                covenantId,
                facts.frontEvidenceId,
                facts.victimEvidenceId,
                facts.backEvidenceId
            )
        );
        _settle(rulingId, covenantId, covenant, RulingKind.SANDWICH, breachHeight, facts.affectedUser, recoveryPool);
    }

    function _verifyRelayRouteAuthorization(
        bytes32 covenantId,
        CovenantBook.Covenant memory covenant,
        uint64 victimHeight,
        SandwichFacts memory facts,
        address authorizationSigner,
        RelayRouteAuthorization calldata authorization
    ) private {
        if (authorization.validUntilHeight < victimHeight) {
            revert AuthorizationExpired(victimHeight, authorization.validUntilHeight);
        }
        if (authorization.validUntilHeight > covenant.validUntilHeight) {
            revert AuthorizationExceedsCoverage(authorization.validUntilHeight, covenant.validUntilHeight);
        }
        bytes32 digest = sandwichAuthorizationDigest(
            covenantId,
            covenant.chainKey,
            facts.affectedUser,
            facts.victimNonce,
            facts.victimTo,
            facts.victimValue,
            facts.victimCallDataHash,
            authorization.validUntilHeight
        );
        address signer = _recoverRelaySigner(digest, authorization.signature);
        if (signer != authorizationSigner) revert InvalidAuthorizationSigner(authorizationSigner, signer);
        emit RelayRouteAuthorizationVerified(covenantId, digest, authorizationSigner, authorization.validUntilHeight);
    }

    function _recoverRelaySigner(bytes32 digest, bytes calldata signature) private pure returns (address signer) {
        if (signature.length != ECDSA_SIGNATURE_LENGTH) {
            revert InvalidAuthorizationSignatureLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        if (uint256(s) == 0 || uint256(s) > SECP256K1_HALF_ORDER) revert InvalidAuthorizationS(s);
        if (v != 27 && v != 28) revert InvalidAuthorizationV(v);
        signer = ecrecover(digest, v, r, s);
    }

    function _assertSandwichFlows(SwapAmounts[] memory swaps, bool numeraireIsToken0) private pure {
        DirectedFlow memory front = _orient(swaps[0], numeraireIsToken0);
        DirectedFlow memory victim = _orient(swaps[1], numeraireIsToken0);
        DirectedFlow memory back = _orient(swaps[2], numeraireIsToken0);
        _assertFrontOrVictimBuy(front, 0);
        _assertFrontOrVictimBuy(victim, 1);
        _assertBackSell(back, 2);
        if (back.counterIn > front.counterOut) {
            revert CounterAssetNotConserved(front.counterOut, back.counterIn);
        }
        if (back.numeraireOut <= front.numeraireIn) {
            revert NoGrossPositiveCycle(front.numeraireIn, back.numeraireOut);
        }
    }

    function _verifyFifo(
        CovenantBook.Covenant memory covenant,
        SourceTransactionProof[] calldata proofs,
        address processingSigner
    ) private returns (FifoFacts memory facts) {
        VerifiedTransaction[] memory proven = new VerifiedTransaction[](4);
        DecodedEvmTransaction[] memory decoded = new DecodedEvmTransaction[](4);
        for (uint256 i; i < 4; ++i) {
            _assertCovered(covenant, proofs[i].context.chainKey, proofs[i].context.blockHeight, i);
            proven[i] = _verifyTransaction(proofs[i].context, proofs[i].inclusion, i);
            decoded[i] = _decodeSuccessful(proofs[i].inclusion.encodedTransaction, i);
        }

        ExitFact memory requestA = _exactExitEvent(decoded[0].receipt, covenant.sourceContract, EXIT_REQUESTED, 0);
        ExitFact memory requestB = _exactExitEvent(decoded[1].receipt, covenant.sourceContract, EXIT_REQUESTED, 1);
        ExitFact memory processB = _exactExitEvent(decoded[2].receipt, covenant.sourceContract, EXIT_PROCESSED, 2);
        ExitFact memory processA = _exactExitEvent(decoded[3].receipt, covenant.sourceContract, EXIT_PROCESSED, 3);

        if (requestA.requestId >= requestB.requestId) {
            revert RequestIdsNotAscending(requestA.requestId, requestB.requestId);
        }

        _assertFifoOrdering(proven);
        if (decoded[2].from != processingSigner) {
            revert ProcessSenderMismatch(2, processingSigner, decoded[2].from);
        }
        if (decoded[3].from != processingSigner) {
            revert ProcessSenderMismatch(3, processingSigner, decoded[3].from);
        }
        _assertProcessedMatches(2, requestB, processB);
        _assertProcessedMatches(3, requestA, processA);

        facts.requestAEvidenceId = proven[0].evidenceId;
        facts.requestBEvidenceId = proven[1].evidenceId;
        facts.processBEvidenceId = proven[2].evidenceId;
        facts.processAEvidenceId = proven[3].evidenceId;
        facts.requestAId = requestA.requestId;
        facts.requestBId = requestB.requestId;
        // Under the policy-bound unique, non-cancellable request semantics, processing B before A
        // is a completed inversion. The court proves positive history, not arbitrary vault state.
        facts.breachHeight = proven[2].position.blockHeight;
        facts.beneficiary = requestA.owner;
    }

    function _assertFifoOrdering(VerifiedTransaction[] memory proven) private pure {
        OrderingPredicates.assertBefore(proven[0].position, proven[1].position);
        OrderingPredicates.assertBefore(proven[0].position, proven[2].position);
        OrderingPredicates.assertBefore(proven[0].position, proven[3].position);
        OrderingPredicates.assertBefore(proven[1].position, proven[2].position);
        OrderingPredicates.assertBefore(proven[1].position, proven[3].position);
        OrderingPredicates.assertBefore(proven[2].position, proven[3].position);
    }

    function _loadCovenant(bytes32 covenantId, CovenantBook.CovenantType expectedType)
        private
        view
        returns (CovenantBook.Covenant memory covenant)
    {
        covenant = COVENANT_BOOK.covenantOf(covenantId);
        if (covenant.operator == address(0)) revert CovenantNotFound(covenantId);
        if (covenant.covenantType != expectedType) revert WrongCovenantType(expectedType, covenant.covenantType);
        if (covenant.fixedPenalty > type(uint128).max) revert PenaltyDoesNotFitBureauValue(covenant.fixedPenalty);
    }

    function _assertCovered(CovenantBook.Covenant memory covenant, uint64 chainKey, uint64 blockHeight, uint256 proof)
        private
        pure
    {
        if (chainKey != covenant.chainKey) revert WrongSourceChain(proof, covenant.chainKey, chainKey);
        if (blockHeight < covenant.validFromHeight || blockHeight > covenant.validUntilHeight) {
            revert ProofOutsideCoverage(proof, blockHeight, covenant.validFromHeight, covenant.validUntilHeight);
        }
    }

    function _decodeSuccessful(bytes memory encodedTransaction, uint256 proof)
        private
        pure
        returns (DecodedEvmTransaction memory decoded)
    {
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTransactionType(proof, txType);

        EvmV1Decoder.CommonTxFields memory common = EvmV1Decoder.decodeCommonTxFields(encodedTransaction);
        decoded.from = common.from;
        decoded.to = common.to;
        decoded.nonce = common.nonce;
        decoded.value = common.value;
        decoded.callDataHash = keccak256(common.data);
        decoded.receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (decoded.receipt.receiptStatus != 1) revert SourceTransactionReverted(proof);
    }

    function _exactEventSwap(EvmV1Decoder.ReceiptFields memory receipt, address pool, uint256 proof)
        private
        pure
        returns (SwapAmounts memory swap)
    {
        uint256 matches;
        for (uint256 i; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory logEntry = receipt.receiptLogs[i];
            if (logEntry.address_ != pool || logEntry.topics.length == 0 || logEntry.topics[0] != UNISWAP_V2_SWAP) {
                continue;
            }
            ++matches;
            if (matches > 1) revert ExpectedEventAmbiguous(proof, pool, UNISWAP_V2_SWAP, matches);
            if (logEntry.topics.length != EXPECTED_SWAP_TOPICS || logEntry.data.length != SWAP_DATA_LENGTH) {
                revert MalformedEvent(proof, logEntry.topics.length, logEntry.data.length);
            }
            (swap.amount0In, swap.amount1In, swap.amount0Out, swap.amount1Out) =
                abi.decode(logEntry.data, (uint256, uint256, uint256, uint256));
        }
        if (matches == 0) revert ExpectedEventMissing(proof, pool, UNISWAP_V2_SWAP);
    }

    function _exactExitEvent(
        EvmV1Decoder.ReceiptFields memory receipt,
        address vault,
        bytes32 eventSignature,
        uint256 proof
    ) private pure returns (ExitFact memory fact) {
        uint256 matches;
        for (uint256 i; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory logEntry = receipt.receiptLogs[i];
            if (logEntry.address_ != vault || logEntry.topics.length == 0 || logEntry.topics[0] != eventSignature) {
                continue;
            }
            ++matches;
            if (matches > 1) revert ExpectedEventAmbiguous(proof, vault, eventSignature, matches);
            if (logEntry.topics.length != EXPECTED_EXIT_TOPICS || logEntry.data.length != EXIT_DATA_LENGTH) {
                revert MalformedEvent(proof, logEntry.topics.length, logEntry.data.length);
            }
            fact.requestId = uint256(logEntry.topics[1]);
            fact.owner = _indexedAddress(logEntry.topics[2], proof);
            fact.amount = abi.decode(logEntry.data, (uint256));
        }
        if (matches == 0) revert ExpectedEventMissing(proof, vault, eventSignature);
    }

    function _indexedAddress(bytes32 topic, uint256 proof) private pure returns (address decoded) {
        uint256 raw = uint256(topic);
        if (raw >> 160 != 0) revert MalformedIndexedAddress(proof, topic);
        // The upper 96 bits were explicitly checked above.
        // forge-lint: disable-next-line(unsafe-typecast)
        decoded = address(uint160(raw));
    }

    function _orient(SwapAmounts memory swap, bool numeraireIsToken0) private pure returns (DirectedFlow memory flow) {
        if (numeraireIsToken0) {
            flow = DirectedFlow({
                numeraireIn: swap.amount0In,
                numeraireOut: swap.amount0Out,
                counterIn: swap.amount1In,
                counterOut: swap.amount1Out
            });
        } else {
            flow = DirectedFlow({
                numeraireIn: swap.amount1In,
                numeraireOut: swap.amount1Out,
                counterIn: swap.amount0In,
                counterOut: swap.amount0Out
            });
        }
    }

    function _assertFrontOrVictimBuy(DirectedFlow memory flow, uint256 proof) private pure {
        if (flow.numeraireIn == 0 || flow.numeraireOut != 0 || flow.counterIn != 0 || flow.counterOut == 0) {
            revert InvalidSwapDirection(proof);
        }
    }

    function _assertBackSell(DirectedFlow memory flow, uint256 proof) private pure {
        if (flow.numeraireIn != 0 || flow.numeraireOut == 0 || flow.counterIn == 0 || flow.counterOut != 0) {
            revert InvalidSwapDirection(proof);
        }
    }

    function _assertProcessedMatches(uint256 proof, ExitFact memory request, ExitFact memory processed) private pure {
        if (processed.requestId != request.requestId) {
            revert ProcessedRequestMismatch(proof, request.requestId, processed.requestId);
        }
        if (processed.owner != request.owner) revert ProcessedOwnerMismatch(proof, request.owner, processed.owner);
    }

    function _settle(
        bytes32 rulingId,
        bytes32 covenantId,
        CovenantBook.Covenant memory covenant,
        RulingKind rulingKind,
        uint64 breachHeight,
        address affectedUser,
        address beneficiary
    ) private {
        if (_rulings[rulingId].covenantId != bytes32(0)) revert RulingAlreadyExists(rulingId);

        (uint256 paid, uint256 shortfall) = COVENANT_BOOK.settleBreach(covenantId, rulingId, breachHeight, beneficiary);

        _rulings[rulingId] = Ruling({
            covenantId: covenantId,
            kind: rulingKind,
            operator: covenant.operator,
            affectedUser: affectedUser,
            beneficiary: beneficiary,
            breachHeight: breachHeight,
            // forge-lint: disable-next-line(unsafe-typecast)
            ruledAt: uint64(block.timestamp),
            paid: paid,
            shortfall: shortfall,
            bureauRecorded: false
        });
        _rulingIds.push(rulingId);

        _tryRecordBureauEvidence(rulingId, _rulings[rulingId]);

        emit OrderingBreachRuled(
            rulingId,
            covenantId,
            rulingKind,
            covenant.operator,
            affectedUser,
            beneficiary,
            breachHeight,
            paid,
            shortfall
        );
    }

    function _tryRecordBureauEvidence(bytes32 rulingId, Ruling storage ruling) private returns (bool recorded) {
        PerformanceBureau.EvidenceKind evidenceKind = ruling.kind == RulingKind.SANDWICH
            ? PerformanceBureau.EvidenceKind.SandwichBreach
            : PerformanceBureau.EvidenceKind.FifoBreach;

        // The penalty was bounded before verification, and `paid` cannot exceed it.
        // forge-lint: disable-next-line(unsafe-typecast)
        try PERFORMANCE_BUREAU.recordEvidence(
            ruling.operator, rulingId, evidenceKind, uint128(ruling.paid), ruling.shortfall != 0
        ) {
            ruling.bureauRecorded = true;
            emit BureauEvidenceRecorded(rulingId);
            return true;
        } catch (bytes memory revertData) {
            emit BureauEvidenceDeferred(rulingId, keccak256(revertData));
            return false;
        }
    }
}
