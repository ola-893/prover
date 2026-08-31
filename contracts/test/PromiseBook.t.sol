// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PromiseBook, IPromiseAttestedHeightSource } from "../src/PromiseBook.sol";
import { PromiseSourceRegistry } from "../src/PromiseSourceRegistry.sol";
import { TestBase } from "./TestBase.sol";

contract MockPromiseAttestedHeightSource is IPromiseAttestedHeightSource {
    mapping(uint64 chainKey => HeightHashResult result) internal _tips;

    function setTip(uint64 chainKey, uint64 height, bool isAttestation, bool exists) external {
        _tips[chainKey] = HeightHashResult({
            height: height,
            hash: keccak256(abi.encode("attestation", chainKey, height)),
            isAttestation: isAttestation,
            exists: exists
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

contract MockPromise1271Beneficiary {
    bytes32 public acceptedDigest;
    bytes4 public response = 0x1626ba7e;
    bool public shouldRevert;

    function configure(bytes32 digest, bytes4 response_, bool shouldRevert_) external {
        acceptedDigest = digest;
        response = response_;
        shouldRevert = shouldRevert_;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        if (shouldRevert) revert("wallet rejected");
        if (digest != acceptedDigest) return 0xffffffff;
        return response;
    }
}

contract PromiseBookTest is TestBase {
    uint64 private constant CHAIN_KEY = 3;
    uint64 private constant INITIAL_TIP = 1_000;
    uint256 private constant BENEFICIARY_KEY = 0xB0B;
    address private constant ACTOR = address(0xA11CE);
    address private constant OTHER = address(0xBAD);
    address private constant SOURCE = address(0x5150);
    bytes32 private constant TERMS_HASH = keccak256("rfq-terms-v4");
    bytes32 private constant RFQ_POLICY_ID = keccak256("PROVER_PROMISE_RFQ_EXECUTED_V1");
    bytes32 private constant SETTLEMENT_POLICY_ID = keccak256("PROVER_PROMISE_SETTLEMENT_RELEASED_V1");
    bytes32 private constant ENTROPY_HASH = keccak256("future-creditcoin-block");
    uint256 private constant BOND = 30 ether;
    uint256 private constant PENALTY = 10 ether;

    address private beneficiary;
    MockPromiseAttestedHeightSource private chainInfo;
    PromiseSourceRegistry private registry;
    PromiseCourtCaller private promiseCourt;
    PromiseBook private book;

    function setUp() public {
        beneficiary = vm.addr(BENEFICIARY_KEY);
        chainInfo = new MockPromiseAttestedHeightSource();
        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true, true);
        registry = new PromiseSourceRegistry(address(this));
        registry.setSourceApproval(uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, SOURCE, RFQ_POLICY_ID, true);
        registry.setSourceApproval(
            uint8(PromiseBook.PromiseKind.SETTLEMENT), CHAIN_KEY, SOURCE, SETTLEMENT_POLICY_ID, true
        );
        promiseCourt = new PromiseCourtCaller();
        book = new PromiseBook(address(chainInfo), address(registry));
        book.initializeCourt(address(promiseCourt));
        vm.deal(ACTOR, 1_000 ether);
    }

    function test_CourtCanOnlyBeInitializedOnceByDeployer() public {
        PromiseBook freshBook = new PromiseBook(address(chainInfo), address(registry));

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.NotDeployer.selector, OTHER));
        freshBook.initializeCourt(address(promiseCourt));

        freshBook.initializeCourt(address(promiseCourt));
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.CourtAlreadyInitialized.selector, address(promiseCourt)));
        freshBook.initializeCourt(OTHER);
    }

    function test_RegisterDraftRequiresCourtApprovalExactBondAndBeneficiarySignature() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 7);
        bytes memory signature = _sign(params);

        PromiseBook freshBook = new PromiseBook(address(chainInfo), address(registry));
        vm.prank(ACTOR);
        vm.expectRevert(PromiseBook.CourtNotInitialized.selector);
        freshBook.registerDraft{ value: BOND }(params, signature);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.IncorrectBond.selector, BOND - 1, BOND));
        book.registerDraft{ value: BOND - 1 }(params, signature);

        bytes memory wrongSignature = _signForKey(params, 0xC0FFEE);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidBeneficiarySignature.selector, beneficiary));
        book.registerDraft{ value: BOND }(params, wrongSignature);

        params.adapterRevision = 9;
        signature = _sign(params);
        bytes32 key = registry.sourceKey(uint8(params.kind), CHAIN_KEY, SOURCE, RFQ_POLICY_ID);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.SourceRevisionMismatch.selector, key, uint64(9), uint64(1)));
        book.registerDraft{ value: BOND }(params, signature);
    }

    function test_RegistrationStoresAuthorizationButDoesNotCreatePerformance() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 300);
        bytes32 digest = book.draftAuthorizationDigest(ACTOR, params);
        bytes32 draftId = _register(params);
        PromiseBook.DraftRecord memory draft = book.draftOf(draftId);

        assertEq(draft.actor, ACTOR);
        assertEq(draft.params.beneficiary, beneficiary);
        assertEq(draft.params.policyId, RFQ_POLICY_ID);
        assertEq(draft.authorizationDigest, digest);
        assertEq(uint256(draft.status), uint256(PromiseBook.DraftStatus.PENDING));
        assertEq(draft.promiseId, bytes32(0));
        assertTrue(book.beneficiaryNonceUsed(beneficiary, 300));
        assertEq(book.nextDraftNonce(ACTOR), 1);

        (uint64 opened,,,, uint256 posted,) = book.actorStats(ACTOR);
        assertEq(opened, 0);
        assertEq(posted, 0);
    }

    function test_AuthorizationReplayAndBeneficiaryNonceInvalidationFail() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 257);
        bytes memory signature = _sign(params);
        vm.prank(ACTOR);
        book.registerDraft{ value: BOND }(params, signature);

        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.BeneficiaryNonceAlreadyUsed.selector, beneficiary, uint256(257))
        );
        book.registerDraft{ value: BOND }(params, signature);

        PromiseBook.DraftParams memory invalidated = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 513);
        vm.prank(beneficiary);
        book.invalidateBeneficiaryNonces(2, uint256(1) << 1);
        assertTrue(book.beneficiaryNonceUsed(beneficiary, 513));
        bytes memory invalidatedSignature = _sign(invalidated);
        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.BeneficiaryNonceAlreadyUsed.selector, beneficiary, uint256(513))
        );
        book.registerDraft{ value: BOND }(invalidated, invalidatedSignature);
    }

    function test_ChangingAnySignedEconomicFieldInvalidatesSignature() public {
        PromiseBook.DraftParams memory authorized = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 10);
        bytes memory signature = _sign(authorized);
        authorized.fixedPenalty += 1;

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidBeneficiarySignature.selector, beneficiary));
        book.registerDraft{ value: BOND }(authorized, signature);
        assertFalse(book.beneficiaryNonceUsed(beneficiary, 10));
        assertEq(book.nextDraftNonce(ACTOR), 0);
    }

    function test_Eip2098AndEip1271BeneficiariesAreSupported() public {
        PromiseBook.DraftParams memory compactParams = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 11);
        bytes32 digest = book.draftAuthorizationDigest(ACTOR, compactParams);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BENEFICIARY_KEY, digest);
        bytes32 vs = bytes32(uint256(s) | (uint256(v - 27) << 255));
        vm.prank(ACTOR);
        book.registerDraft{ value: BOND }(compactParams, bytes.concat(r, vs));

        MockPromise1271Beneficiary wallet = new MockPromise1271Beneficiary();
        PromiseBook.DraftParams memory walletParams = _params(PromiseBook.PromiseKind.SETTLEMENT, 12);
        walletParams.beneficiary = address(wallet);
        bytes32 walletDigest = book.draftAuthorizationDigest(ACTOR, walletParams);
        wallet.configure(walletDigest, 0x1626ba7e, false);
        vm.prank(ACTOR);
        book.registerDraft{ value: BOND }(walletParams, hex"1234");

        walletParams.beneficiaryNonce = 13;
        walletParams.entropyBlock += 1;
        walletParams.activationDeadlineBlock += 1;
        walletDigest = book.draftAuthorizationDigest(ACTOR, walletParams);
        wallet.configure(walletDigest, 0xffffffff, false);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidBeneficiarySignature.selector, address(wallet)));
        book.registerDraft{ value: BOND }(walletParams, hex"1234");
    }

    function test_EoaSignaturesRejectMalformedLengthHighSAndInvalidV() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 130);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidSignatureLength.selector, uint256(63)));
        book.registerDraft{ value: BOND }(params, new bytes(63));

        bytes memory highS = bytes.concat(bytes32(uint256(1)), bytes32(type(uint256).max), bytes1(uint8(27)));
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidSignatureS.selector, bytes32(type(uint256).max)));
        book.registerDraft{ value: BOND }(params, highS);

        bytes32 digest = book.draftAuthorizationDigest(ACTOR, params);
        (, bytes32 r, bytes32 s) = vm.sign(BENEFICIARY_KEY, digest);
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.InvalidSignatureV.selector, uint8(29)));
        book.registerDraft{ value: BOND }(params, bytes.concat(r, s, bytes1(uint8(29))));
        assertFalse(book.beneficiaryNonceUsed(beneficiary, 130));
    }

    function test_DraftTimingAndSelfBeneficiaryAreRejected() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 14);
        params.entropyBlock = uint64(block.number + 1);
        params.activationDeadlineBlock = params.entropyBlock + 20;
        vm.prank(ACTOR);
        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.EntropyBlockNotFuture.selector, params.entropyBlock, block.number + 2)
        );
        book.registerDraft{ value: BOND }(params, hex"");

        params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 15);
        params.activationLeadBlocks = 63;
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.ActivationLeadTooShort.selector, uint64(63), uint64(64)));
        book.registerDraft{ value: BOND }(params, hex"");

        params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 16);
        params.beneficiary = ACTOR;
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.ActorIsBeneficiary.selector, ACTOR));
        book.registerDraft{ value: BOND }(params, hex"");
    }

    function test_ActivationRequiresMinedNonzeroAnchorAndIsPermissionless() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 17);
        bytes32 draftId = _register(params);

        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseBook.ActivationTooEarly.selector,
                block.number,
                uint256(params.entropyBlock + book.MIN_ANCHOR_CONFIRMATIONS())
            )
        );
        book.activateDraft(draftId);

        vm.roll(params.entropyBlock + book.MIN_ANCHOR_CONFIRMATIONS());
        vm.setBlockhash(params.entropyBlock, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.EntropyHashUnavailable.selector, params.entropyBlock));
        book.activateDraft(draftId);

        vm.setBlockhash(params.entropyBlock, ENTROPY_HASH);
        vm.prank(OTHER);
        bytes32 promiseId = book.activateDraft(draftId);
        assertTrue(promiseId != bytes32(0));
    }

    function test_ActivationDerivesExactHeightsStoresEntropyAndStartsStats() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.SETTLEMENT, 18);
        bytes32 draftId = _register(params);
        bytes32 promiseId = _activate(draftId, params);
        PromiseBook.PromiseRecord memory record = book.promiseOf(promiseId);

        assertEq(record.terms.actor, ACTOR);
        assertEq(record.terms.beneficiary, beneficiary);
        assertEq(record.terms.policyId, SETTLEMENT_POLICY_ID);
        assertEq(record.terms.sourcePolicyRevision, 1);
        assertEq(record.terms.validFromHeight, 1_100);
        assertEq(record.terms.fulfillmentDeadlineHeight, 1_500);
        assertEq(record.terms.proofDeadlineHeight, 1_700);
        assertEq(record.draftId, draftId);
        assertEq(record.entropyHash, ENTROPY_HASH);
        assertEq(record.activationAttestedHeight, INITIAL_TIP);
        assertEq(record.activationAttestationHash, keccak256(abi.encode("attestation", CHAIN_KEY, INITIAL_TIP)));

        PromiseBook.DraftRecord memory draft = book.draftOf(draftId);
        assertEq(uint256(draft.status), uint256(PromiseBook.DraftStatus.ACTIVATED));
        assertEq(draft.promiseId, promiseId);
        (uint64 opened,,,, uint256 posted,) = book.actorStats(ACTOR);
        assertEq(opened, 1);
        assertEq(posted, BOND);
    }

    function test_ActivationRetentionBoundaryIsInclusiveAndExpiryStartsAfterDeadline() public {
        PromiseBook.DraftParams memory atBoundary = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 131);
        atBoundary.activationDeadlineBlock = atBoundary.entropyBlock + book.BLOCKHASH_RETENTION();
        bytes32 boundaryDraft = _register(atBoundary);
        vm.roll(atBoundary.activationDeadlineBlock);
        vm.setBlockhash(atBoundary.entropyBlock, ENTROPY_HASH);
        assertTrue(book.activateDraft(boundaryDraft) != bytes32(0));

        PromiseBook.DraftParams memory expired = _params(PromiseBook.PromiseKind.SETTLEMENT, 132);
        expired.activationDeadlineBlock = expired.entropyBlock + book.BLOCKHASH_RETENTION();
        bytes32 expiredDraft = _register(expired);
        vm.roll(expired.activationDeadlineBlock + 1);
        vm.setBlockhash(expired.entropyBlock, ENTROPY_HASH);
        vm.expectRevert(
            abi.encodeWithSelector(
                PromiseBook.ActivationWindowClosed.selector, block.number, expired.activationDeadlineBlock
            )
        );
        book.activateDraft(expiredDraft);
        book.expireDraft(expiredDraft);
        assertEq(uint256(book.draftOf(expiredDraft).status), uint256(PromiseBook.DraftStatus.EXPIRED));
    }

    function test_RegistryChangeUnwindsPendingDraftButCannotStrandActivePromise() public {
        PromiseBook.DraftParams memory pendingParams = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 19);
        bytes32 pendingDraft = _register(pendingParams);
        registry.setSourceApproval(
            uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, SOURCE, RFQ_POLICY_ID, false
        );
        registry.setSourceApproval(uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, SOURCE, RFQ_POLICY_ID, true);

        vm.prank(OTHER);
        book.expireDraft(pendingDraft);
        assertEq(uint256(book.draftOf(pendingDraft).status), uint256(PromiseBook.DraftStatus.EXPIRED));
        assertEq(book.claimable(ACTOR), BOND);

        PromiseBook.DraftParams memory activeParams = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 20);
        activeParams.adapterRevision = 3;
        bytes32 activeDraft = _register(activeParams);
        bytes32 promiseId = _activate(activeDraft, activeParams);
        registry.setSourceApproval(
            uint8(PromiseBook.PromiseKind.RFQ_EXECUTION), CHAIN_KEY, SOURCE, RFQ_POLICY_ID, false
        );

        chainInfo.setTip(CHAIN_KEY, 1_300, true, true);
        promiseCourt.resolve(book, promiseId, keccak256("fulfilled"), 1_200, PromiseBook.Outcome.FULFILLED);
        assertEq(uint256(book.promiseOf(promiseId).outcome), uint256(PromiseBook.Outcome.FULFILLED));
    }

    function test_ExpiredActivationWindowRefundsWithoutPerformanceRecord() public {
        PromiseBook.DraftParams memory params = _params(PromiseBook.PromiseKind.SETTLEMENT, 21);
        bytes32 draftId = _register(params);
        vm.roll(params.activationDeadlineBlock + 1);

        vm.prank(OTHER);
        book.expireDraft(draftId);
        assertEq(book.claimable(ACTOR), BOND);
        (uint64 opened, uint64 fulfilled, uint64 breached, uint64 defaulted, uint256 posted,) = book.actorStats(ACTOR);
        assertEq(opened, 0);
        assertEq(fulfilled, 0);
        assertEq(breached, 0);
        assertEq(defaulted, 0);
        assertEq(posted, 0);

        vm.expectRevert(
            abi.encodeWithSelector(PromiseBook.DraftNotPending.selector, draftId, PromiseBook.DraftStatus.EXPIRED)
        );
        book.expireDraft(draftId);
    }

    function test_EvidenceResolutionAndDefaultRetainInclusiveHeightSemantics() public {
        PromiseBook.DraftParams memory fulfilledParams = _params(PromiseBook.PromiseKind.RFQ_EXECUTION, 22);
        bytes32 fulfilledId = _activate(_register(fulfilledParams), fulfilledParams);
        chainInfo.setTip(CHAIN_KEY, 1_500, true, true);
        promiseCourt.resolve(book, fulfilledId, keccak256("edge-fill"), 1_500, PromiseBook.Outcome.FULFILLED);
        assertEq(book.claimable(ACTOR), BOND);

        PromiseBook.DraftParams memory defaultParams = _params(PromiseBook.PromiseKind.SETTLEMENT, 23);
        defaultParams.entropyBlock = uint64(block.number + 2);
        defaultParams.activationDeadlineBlock = defaultParams.entropyBlock + 20;
        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true, true);
        bytes32 defaultId = _activate(_register(defaultParams), defaultParams);
        chainInfo.setTip(CHAIN_KEY, 1_700, true, true);
        vm.expectRevert(abi.encodeWithSelector(PromiseBook.ProofWindowStillOpen.selector, uint64(1_700), uint64(1_700)));
        book.finalizeProofSubmissionDefault(defaultId);

        chainInfo.setTip(CHAIN_KEY, 1_701, true, true);
        vm.prank(OTHER);
        book.finalizeProofSubmissionDefault(defaultId);
        assertEq(uint256(book.promiseOf(defaultId).outcome), uint256(PromiseBook.Outcome.DEFAULTED));
        assertEq(book.claimable(beneficiary), PENALTY);
    }

    function _params(PromiseBook.PromiseKind kind, uint256 beneficiaryNonce)
        private
        view
        returns (PromiseBook.DraftParams memory params)
    {
        uint64 entropyBlock = uint64(block.number + 2);
        params = PromiseBook.DraftParams({
            kind: kind,
            beneficiary: beneficiary,
            sourceChainKey: CHAIN_KEY,
            sourceContract: SOURCE,
            policyId: kind == PromiseBook.PromiseKind.RFQ_EXECUTION ? RFQ_POLICY_ID : SETTLEMENT_POLICY_ID,
            adapterRevision: 1,
            termsHash: TERMS_HASH,
            activationLeadBlocks: 100,
            fulfillmentWindowBlocks: 401,
            proofSubmissionWindowBlocks: 200,
            entropyBlock: entropyBlock,
            activationDeadlineBlock: entropyBlock + 20,
            fixedPenalty: PENALTY,
            bond: BOND,
            beneficiaryNonce: beneficiaryNonce
        });
    }

    function _sign(PromiseBook.DraftParams memory params) private returns (bytes memory) {
        return _signForKey(params, BENEFICIARY_KEY);
    }

    function _signForKey(PromiseBook.DraftParams memory params, uint256 key) private returns (bytes memory) {
        bytes32 digest = book.draftAuthorizationDigest(ACTOR, params);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return bytes.concat(r, s, bytes1(v));
    }

    function _register(PromiseBook.DraftParams memory params) private returns (bytes32 draftId) {
        bytes memory signature = _sign(params);
        vm.prank(ACTOR);
        draftId = book.registerDraft{ value: params.bond }(params, signature);
    }

    function _activate(bytes32 draftId, PromiseBook.DraftParams memory params) private returns (bytes32 promiseId) {
        vm.roll(params.entropyBlock + book.MIN_ANCHOR_CONFIRMATIONS());
        vm.setBlockhash(params.entropyBlock, ENTROPY_HASH);
        promiseId = book.activateDraft(draftId);
    }
}
