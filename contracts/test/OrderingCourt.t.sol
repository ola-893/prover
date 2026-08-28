// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CovenantBook, IAttestedHeightSource } from "../src/CovenantBook.sol";
import { OrderingCourt } from "../src/OrderingCourt.sol";
import { OrderingCourtDeployer } from "../src/OrderingCourtDeployer.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { PolicyV1 } from "../src/PolicyV1.sol";
import { AttestcoinProofAdapter } from "../src/attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "../src/attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "../src/attestcoin/INativeQueryVerifier.sol";
import { OrderingPredicates } from "../src/attestcoin/OrderingPredicates.sol";
import { EvmV1Fixture } from "./helpers/EvmV1Fixture.sol";
import { MockNativeQueryVerifier } from "./mocks/MockNativeQueryVerifier.sol";
import { TestBase } from "./TestBase.sol";

contract OrderingCourtHeightSource is IAttestedHeightSource {
    mapping(uint64 chainKey => HeightHashResult result) private _tips;

    function setTip(uint64 chainKey, uint64 height, bool exists) external {
        _tips[chainKey] = HeightHashResult({
            height: height, hash: keccak256(abi.encode(chainKey, height)), isAttestation: true, exists: exists
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

contract OrderingCourtTest is TestBase {
    uint256 private constant OPERATOR_KEY = 0xA11CE;
    uint256 private constant FORGER_KEY = 0xBAD;

    uint64 private constant CHAIN_KEY = 1;
    uint64 private constant INITIAL_TIP = 1_000;
    uint64 private constant VALID_FROM = 1_100;
    uint64 private constant VALID_UNTIL = 2_000;
    uint64 private constant SANDWICH_HEIGHT = 1_200;
    uint64 private constant PROCESS_HEIGHT = 1_201;

    address private constant SEARCHER = address(0x5EA2C4);
    address private constant VICTIM = address(0xB0B);
    address private constant ROUTER = address(0xA0B0C0);
    address private constant POOL = address(0xC0FFEE);
    address private constant RECOVERY_POOL = address(0xAEC0);
    address private constant OTHER_RECOVERY_POOL = address(0xBEEF);
    address private constant VAULT = address(0xFA17);
    address private constant OWNER_A = address(0xA001);
    address private constant OWNER_B = address(0xB002);

    bytes32 private constant SANDWICH_ROOT = keccak256("sandwich-root");
    bytes32 private constant REQUEST_ROOT = keccak256("request-root");
    bytes32 private constant PROCESS_ROOT = keccak256("process-root");
    bytes32 private constant SWAP_SIGNATURE = keccak256("Swap(address,uint256,uint256,uint256,uint256,address)");
    bytes32 private constant REQUEST_SIGNATURE = keccak256("ExitRequested(uint256,address,uint256)");
    bytes32 private constant PROCESS_SIGNATURE = keccak256("ExitProcessed(uint256,address,uint256)");

    OrderingCourtHeightSource private heightSource;
    MockNativeQueryVerifier private verifier;
    PerformanceBureau private bureau;
    CovenantBook private book;
    OrderingCourt private court;
    address private operator;

    function setUp() public {
        operator = vm.addr(OPERATOR_KEY);
        heightSource = new OrderingCourtHeightSource();
        heightSource.setTip(CHAIN_KEY, INITIAL_TIP, true);
        verifier = new MockNativeQueryVerifier();
        bureau = new PerformanceBureau();

        OrderingCourtDeployer deployer = new OrderingCourtDeployer(verifier, heightSource, bureau);
        book = deployer.COVENANT_BOOK();
        court = deployer.ORDERING_COURT();
        assertEq(address(court), deployer.PREDICTED_COURT());

        uint256 permissionMask = bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.FifoBreach);
        bureau.setReporterPermissions(address(court), permissionMask);
        vm.deal(operator, 1_000 ether);
    }

    function test_ProvesAdjacentPositionsAndSettlesAuthorizedSandwichWarranty() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);

        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);
        bytes32 rulingId =
            court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);

        OrderingCourt.Ruling memory ruling = court.rulingOf(rulingId);
        assertEq(ruling.covenantId, covenantId);
        assertEq(uint256(ruling.kind), uint256(OrderingCourt.RulingKind.SANDWICH));
        assertEq(ruling.operator, operator);
        assertEq(ruling.affectedUser, VICTIM);
        assertEq(ruling.beneficiary, RECOVERY_POOL);
        assertEq(ruling.breachHeight, SANDWICH_HEIGHT);
        assertEq(ruling.paid, 10 ether);
        assertEq(ruling.shortfall, 0);
        assertEq(court.rulingCount(), 1);
        assertEq(book.claimable(VICTIM), 0);
        assertEq(book.claimable(RECOVERY_POOL), 10 ether);

        PolicyV1.Profile memory profile = bureau.profileOf(operator);
        assertEq(profile.sandwichBreaches, 1);
        assertEq(profile.totalSlashedCtc, 10 ether);
        PerformanceBureau.EvidenceMeta memory evidence = bureau.evidenceOf(rulingId);
        assertEq(evidence.subject, operator);
        assertEq(uint256(evidence.kind), uint256(PerformanceBureau.EvidenceKind.SandwichBreach));
    }

    function test_SandwichFailsWhenAuthenticatedVictimReceiptReverted() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(0, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectRevert(abi.encodeWithSelector(OrderingCourt.SourceTransactionReverted.selector, uint256(1)));
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_TamperedSandwichTransactionFailsAtVerifierBoundary() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        inclusions[1].encodedTransaction = bytes.concat(inclusions[1].encodedTransaction, hex"00");
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectRevert(abi.encodeWithSelector(AttestcoinProofAdapter.VerificationFailed.selector, uint256(1)));
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichVictimMustCallPromisedEntrypoint() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, address(0xDEAD), 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(OrderingCourt.VictimEntrypointMismatch.selector, ROUTER, address(0xDEAD))
        );
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichRulingCannotBeReplayed() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        bytes32 rulingId =
            court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
        vm.expectRevert(abi.encodeWithSelector(OrderingCourt.RulingAlreadyExists.selector, rulingId));
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichRecoveryPoolMustMatchImmutablePolicy() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);

        bytes32 required = court.sandwichPolicyHash(ROUTER, POOL, false, OTHER_RECOVERY_POOL, operator);
        bytes32 committed = court.sandwichPolicyHash(ROUTER, POOL, false, RECOVERY_POOL, operator);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);
        vm.expectRevert(abi.encodeWithSelector(OrderingCourt.SandwichPolicyMismatch.selector, committed, required));
        court.proveSandwich(covenantId, context, inclusions, POOL, false, OTHER_RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichRequiresRelayOperatorSignature() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, FORGER_KEY);

        vm.expectPartialRevert(OrderingCourt.InvalidAuthorizationSigner.selector);
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichRejectsExpiredRouteAuthorization() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization =
            _authorization(covenantId, OPERATOR_KEY, SANDWICH_HEIGHT - 1, VICTIM, 0, ROUTER, keccak256(""));

        vm.expectRevert(
            abi.encodeWithSelector(OrderingCourt.AuthorizationExpired.selector, SANDWICH_HEIGHT, SANDWICH_HEIGHT - 1)
        );
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichAuthorizationBindsVictimNonceAndCalldata() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 7, hex"deadbeef", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectPartialRevert(OrderingCourt.InvalidAuthorizationSigner.selector);
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichAuthorizationBindsVictimNativeValue() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        inclusions[1] = _inclusion(
            EvmV1Fixture.encodeType2WithCallAndValue(
                VICTIM, ROUTER, 0, "", 1 ether, 1, _singleSwapLog(0, 4 ether, 300 ether, 0)
            ),
            "LLLLRRRR",
            SANDWICH_ROOT
        );
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectPartialRevert(OrderingCourt.InvalidAuthorizationSigner.selector);
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichRequiresExactAdjacency() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        inclusions[0] = _inclusion(inclusions[0].encodedTransaction, "LRLLRRRR", SANDWICH_ROOT);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(OrderingCourt.SandwichLegsNotAdjacent.selector, uint64(13), uint64(15), uint64(16))
        );
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_SandwichCannotSellPreExistingCounterAssetAsProfit() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_001 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                OrderingCourt.CounterAssetNotConserved.selector, uint256(1_000 ether), uint256(1_001 ether)
            )
        );
        court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);
    }

    function test_BureauPermissionCannotCensorBondSettlement() public {
        bytes32 covenantId = _openNoSandwich();
        AttestcoinProofAdapter.BlockContext memory context = _context(SANDWICH_HEIGHT);
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions =
            _sandwichInclusions(1, ROUTER, 0, "", 1_000 ether);
        _allowBatch(context, inclusions);
        OrderingCourt.RelayRouteAuthorization memory authorization = _defaultAuthorization(covenantId, OPERATOR_KEY);
        bureau.setReporterPermissions(address(court), 0);

        bytes32 rulingId =
            court.proveSandwich(covenantId, context, inclusions, POOL, false, RECOVERY_POOL, operator, authorization);

        OrderingCourt.Ruling memory ruling = court.rulingOf(rulingId);
        assertFalse(ruling.bureauRecorded);
        assertEq(book.claimable(RECOVERY_POOL), 10 ether);
        assertEq(bureau.profileOf(operator).sandwichBreaches, 0);

        bureau.setReporterPermissions(
            address(court), bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach)
        );
        assertTrue(court.syncRulingToBureau(rulingId));
        assertTrue(court.rulingOf(rulingId).bureauRecorded);
        assertEq(bureau.profileOf(operator).sandwichBreaches, 1);
    }

    function test_ProvesCrossBlockFifoInversionAndSettlesForEarlierOwner() public {
        bytes32 covenantId = _openFifo();
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(true, OWNER_A);
        _allowFifo(proofs);

        bytes32 rulingId = court.proveFifoInversion(covenantId, proofs, operator);

        OrderingCourt.Ruling memory ruling = court.rulingOf(rulingId);
        assertEq(ruling.covenantId, covenantId);
        assertEq(uint256(ruling.kind), uint256(OrderingCourt.RulingKind.FIFO_INVERSION));
        assertEq(ruling.affectedUser, OWNER_A);
        assertEq(ruling.beneficiary, OWNER_A);
        assertEq(ruling.breachHeight, PROCESS_HEIGHT);
        assertEq(ruling.paid, 10 ether);
        assertEq(book.claimable(OWNER_A), 10 ether);

        PolicyV1.Profile memory profile = bureau.profileOf(operator);
        assertEq(profile.fifoBreaches, 1);
        assertEq(profile.totalSlashedCtc, 10 ether);
    }

    function test_FifoRejectsNormalProcessingOrder() public {
        bytes32 covenantId = _openFifo();
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(false, OWNER_A);
        _allowFifo(proofs);

        vm.expectRevert(
            abi.encodeWithSelector(
                OrderingPredicates.PositionNotBefore.selector, PROCESS_HEIGHT, uint64(17), PROCESS_HEIGHT, uint64(16)
            )
        );
        court.proveFifoInversion(covenantId, proofs, operator);
    }

    function test_FifoRejectsProcessOwnerThatDoesNotMatchRequest() public {
        bytes32 covenantId = _openFifo();
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(true, address(0xBAD));
        _allowFifo(proofs);

        vm.expectRevert(
            abi.encodeWithSelector(OrderingCourt.ProcessedOwnerMismatch.selector, uint256(3), OWNER_A, address(0xBAD))
        );
        court.proveFifoInversion(covenantId, proofs, operator);
    }

    function test_FifoPolicyMustCommitUniqueNonCancellableQueueSemantics() public {
        vm.prank(operator);
        bytes32 covenantId = book.openFifo{ value: 30 ether }(
            CHAIN_KEY, VAULT, VALID_FROM, VALID_UNTIL, keccak256("unrecognized-fifo-policy"), 10 ether
        );
        heightSource.setTip(CHAIN_KEY, 1_500, true);
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(true, OWNER_A);

        bytes32 requiredPolicyHash = court.fifoPolicyHash(VAULT, operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderingCourt.FifoPolicyMismatch.selector, keccak256("unrecognized-fifo-policy"), requiredPolicyHash
            )
        );
        court.proveFifoInversion(covenantId, proofs, operator);
    }

    function test_FifoProcessingTransactionsMustComeFromPolicyBoundSigner() public {
        bytes32 covenantId = _openFifo();
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(true, OWNER_A);
        proofs[2].inclusion.encodedTransaction =
            EvmV1Fixture.encodeType2(OWNER_B, VAULT, 1, _singleExitLog(PROCESS_SIGNATURE, 2, OWNER_B, 190));
        _allowFifo(proofs);

        vm.expectRevert(
            abi.encodeWithSelector(OrderingCourt.ProcessSenderMismatch.selector, uint256(2), operator, OWNER_B)
        );
        court.proveFifoInversion(covenantId, proofs, operator);
    }

    function test_FifoRequiresEveryProofInsideCovenantCoverage() public {
        bytes32 covenantId = _openFifo();
        OrderingCourt.SourceTransactionProof[] memory proofs = _fifoProofs(true, OWNER_A);
        proofs[3].context = _context(VALID_UNTIL + 1);
        _allowFifo(proofs);

        vm.expectRevert(
            abi.encodeWithSelector(
                OrderingCourt.ProofOutsideCoverage.selector, uint256(3), VALID_UNTIL + 1, VALID_FROM, VALID_UNTIL
            )
        );
        court.proveFifoInversion(covenantId, proofs, operator);
    }

    function _openNoSandwich() private returns (bytes32 covenantId) {
        bytes32 policyHash = court.sandwichPolicyHash(ROUTER, POOL, false, RECOVERY_POOL, operator);
        vm.prank(operator);
        covenantId =
            book.openNoSandwich{ value: 30 ether }(CHAIN_KEY, ROUTER, VALID_FROM, VALID_UNTIL, policyHash, 10 ether);
        heightSource.setTip(CHAIN_KEY, 1_500, true);
    }

    function _openFifo() private returns (bytes32 covenantId) {
        bytes32 policyHash = court.fifoPolicyHash(VAULT, operator);
        vm.prank(operator);
        covenantId = book.openFifo{ value: 30 ether }(CHAIN_KEY, VAULT, VALID_FROM, VALID_UNTIL, policyHash, 10 ether);
        heightSource.setTip(CHAIN_KEY, 1_500, true);
    }

    function _defaultAuthorization(bytes32 covenantId, uint256 signerKey)
        private
        returns (OrderingCourt.RelayRouteAuthorization memory authorization)
    {
        return _authorization(covenantId, signerKey, VALID_UNTIL, VICTIM, 0, ROUTER, keccak256(""));
    }

    function _authorization(
        bytes32 covenantId,
        uint256 signerKey,
        uint64 validUntilHeight,
        address victim,
        uint64 nonce,
        address victimTo,
        bytes32 callDataHash
    ) private returns (OrderingCourt.RelayRouteAuthorization memory authorization) {
        bytes32 digest = court.sandwichAuthorizationDigest(
            covenantId, CHAIN_KEY, victim, nonce, victimTo, 0, callDataHash, validUntilHeight
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        authorization.validUntilHeight = validUntilHeight;
        authorization.signature = abi.encodePacked(r, s, v);
    }

    function _sandwichInclusions(
        uint8 victimStatus,
        address victimTo,
        uint64 victimNonce,
        bytes memory victimCallData,
        uint256 backCounterIn
    ) private pure returns (AttestcoinProofAdapter.TransactionInclusion[] memory inclusions) {
        inclusions = new AttestcoinProofAdapter.TransactionInclusion[](3);
        inclusions[0] = _inclusion(
            EvmV1Fixture.encodeType2(SEARCHER, ROUTER, 1, _singleSwapLog(0, 10 ether, 1_000 ether, 0)),
            "RLLLRRRR",
            SANDWICH_ROOT
        );
        inclusions[1] = _inclusion(
            EvmV1Fixture.encodeType2WithCall(
                VICTIM, victimTo, victimNonce, victimCallData, victimStatus, _singleSwapLog(0, 4 ether, 300 ether, 0)
            ),
            "LLLLRRRR",
            SANDWICH_ROOT
        );
        inclusions[2] = _inclusion(
            EvmV1Fixture.encodeType2(SEARCHER, ROUTER, 1, _singleSwapLog(backCounterIn, 0, 0, 11 ether)),
            "RRRRLRRR",
            SANDWICH_ROOT
        );
    }

    function _fifoProofs(bool inverted, address processAOwner)
        private
        view
        returns (OrderingCourt.SourceTransactionProof[] memory proofs)
    {
        proofs = new OrderingCourt.SourceTransactionProof[](4);
        proofs[0] = OrderingCourt.SourceTransactionProof({
            context: _context(SANDWICH_HEIGHT),
            inclusion: _inclusion(
                EvmV1Fixture.encodeType2(OWNER_A, VAULT, 1, _singleExitLog(REQUEST_SIGNATURE, 1, OWNER_A, 100)),
                "RLLLRRRR",
                REQUEST_ROOT
            )
        });
        proofs[1] = OrderingCourt.SourceTransactionProof({
            context: _context(SANDWICH_HEIGHT),
            inclusion: _inclusion(
                EvmV1Fixture.encodeType2(OWNER_B, VAULT, 1, _singleExitLog(REQUEST_SIGNATURE, 2, OWNER_B, 200)),
                "LLLLRRRR",
                REQUEST_ROOT
            )
        });

        bytes memory processBPattern = inverted ? bytes("RRRRLRRR") : bytes("LRRRLRRR");
        bytes memory processAPattern = inverted ? bytes("LRRRLRRR") : bytes("RRRRLRRR");
        proofs[2] = OrderingCourt.SourceTransactionProof({
            context: _context(PROCESS_HEIGHT),
            inclusion: _inclusion(
                EvmV1Fixture.encodeType2(operator, VAULT, 1, _singleExitLog(PROCESS_SIGNATURE, 2, OWNER_B, 190)),
                processBPattern,
                PROCESS_ROOT
            )
        });
        proofs[3] = OrderingCourt.SourceTransactionProof({
            context: _context(PROCESS_HEIGHT),
            inclusion: _inclusion(
                EvmV1Fixture.encodeType2(operator, VAULT, 1, _singleExitLog(PROCESS_SIGNATURE, 1, processAOwner, 95)),
                processAPattern,
                PROCESS_ROOT
            )
        });
    }

    function _singleSwapLog(uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out)
        private
        pure
        returns (EvmV1Decoder.LogEntryTuple[] memory logs)
    {
        logs = new EvmV1Decoder.LogEntryTuple[](1);
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = SWAP_SIGNATURE;
        topics[1] = _addressTopic(SEARCHER);
        topics[2] = _addressTopic(VICTIM);
        logs[0] = EvmV1Decoder.LogEntryTuple({
            address_: POOL, topics: topics, data: abi.encode(amount0In, amount1In, amount0Out, amount1Out)
        });
    }

    function _singleExitLog(bytes32 signature, uint256 requestId, address owner, uint256 amount)
        private
        pure
        returns (EvmV1Decoder.LogEntryTuple[] memory logs)
    {
        logs = new EvmV1Decoder.LogEntryTuple[](1);
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = signature;
        topics[1] = bytes32(requestId);
        topics[2] = _addressTopic(owner);
        logs[0] = EvmV1Decoder.LogEntryTuple({ address_: VAULT, topics: topics, data: abi.encode(amount) });
    }

    function _context(uint64 height) private pure returns (AttestcoinProofAdapter.BlockContext memory context) {
        context.chainKey = CHAIN_KEY;
        context.blockHeight = height;
        context.lowerEndpointDigest = keccak256(abi.encode("lower-endpoint", height));
        context.continuityRoots = new bytes32[](2);
        context.continuityRoots[0] = keccak256(abi.encode("continuity-0", height));
        context.continuityRoots[1] = keccak256(abi.encode("continuity-1", height));
    }

    function _inclusion(bytes memory encodedTransaction, bytes memory pattern, bytes32 root)
        private
        pure
        returns (AttestcoinProofAdapter.TransactionInclusion memory inclusion)
    {
        inclusion.encodedTransaction = encodedTransaction;
        inclusion.merkleRoot = root;
        inclusion.siblings = new INativeQueryVerifier.MerkleProofEntry[](pattern.length);
        for (uint256 i; i < pattern.length; ++i) {
            inclusion.siblings[i] = INativeQueryVerifier.MerkleProofEntry({
                hash: keccak256(abi.encode("sibling", root, i)), isLeft: pattern[i] == "L"
            });
        }
    }

    function _allowBatch(
        AttestcoinProofAdapter.BlockContext memory context,
        AttestcoinProofAdapter.TransactionInclusion[] memory inclusions
    ) private {
        for (uint256 i; i < inclusions.length; ++i) {
            _allow(context, inclusions[i]);
        }
    }

    function _allowFifo(OrderingCourt.SourceTransactionProof[] memory proofs) private {
        for (uint256 i; i < proofs.length; ++i) {
            _allow(proofs[i].context, proofs[i].inclusion);
        }
    }

    function _allow(
        AttestcoinProofAdapter.BlockContext memory context,
        AttestcoinProofAdapter.TransactionInclusion memory inclusion
    ) private {
        INativeQueryVerifier.MerkleProof memory
            merkleProof = INativeQueryVerifier.MerkleProof({ root: inclusion.merkleRoot, siblings: inclusion.siblings });
        INativeQueryVerifier.ContinuityProof memory continuityProof = INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: context.lowerEndpointDigest, roots: context.continuityRoots
        });
        verifier.allowProof(
            context.chainKey, context.blockHeight, inclusion.encodedTransaction, merkleProof, continuityProof
        );
    }

    function _addressTopic(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}
