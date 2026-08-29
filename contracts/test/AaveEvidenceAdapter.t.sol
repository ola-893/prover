// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AaveEvidenceAdapter, NativeAaveEvidenceAdapter } from "../src/AaveEvidenceAdapter.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { PolicyV1 } from "../src/PolicyV1.sol";
import { AttestcoinProofAdapter } from "../src/attestcoin/AttestcoinProofAdapter.sol";
import { EvmV1Decoder } from "../src/attestcoin/EvmV1Decoder.sol";
import { INativeQueryVerifier } from "../src/attestcoin/INativeQueryVerifier.sol";
import { MockNativeQueryVerifier } from "./mocks/MockNativeQueryVerifier.sol";
import { TestBase } from "./TestBase.sol";

contract AaveEvidenceAdapterTest is TestBase {
    uint64 private constant CHAIN_KEY = 3;
    address private constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address private constant SUBJECT = address(0xCAFE);
    address private constant BORROW_USER = address(0xB0110);
    address private constant THIRD_PARTY = address(0xB0B);
    address private constant OTHER = address(0xBAD);

    // Public Ethereum receipt coordinates inspected from the canonical Aave V3 Pool. The unit
    // tests reconstruct these facts at the mock-verifier boundary; they do not claim to exercise
    // a live CC3 proof. The pinned coordinates are inputs for a separate network integration run.
    address private constant REAL_WALLET = 0x5D99551ce4a2c1467aDF632474424E7e22c72C66;
    bytes32 private constant REAL_BORROW_TX = 0xbcacb57223f15070dec270cede4eed03deb60ecb117d35d8fe518a66d1c590ff;
    bytes32 private constant REAL_REPAY_TX = 0x84ea8dcff1eedb9973b8cc950d497f271e56c1d80e172187710721bfd02ba344;
    uint64 private constant REAL_BORROW_BLOCK = 25_854_707;
    uint64 private constant REAL_REPAY_BLOCK = 25_854_747;
    uint64 private constant REAL_BORROW_TX_INDEX = 201;
    uint64 private constant REAL_REPAY_TX_INDEX = 120;
    uint64 private constant REAL_BORROW_RECEIPT_LOG_ORDINAL = 4;
    uint64 private constant REAL_REPAY_RECEIPT_LOG_ORDINAL = 4;
    uint128 private constant REAL_BORROW_AMOUNT = 90_000e6;
    uint128 private constant REAL_REPAY_AMOUNT = 90_000_055_729;

    MockNativeQueryVerifier private verifier;
    PerformanceBureau private bureau;
    AaveEvidenceAdapter private adapter;

    function setUp() public {
        verifier = new MockNativeQueryVerifier();
        bureau = new PerformanceBureau();
        adapter = new AaveEvidenceAdapter(verifier, bureau);

        uint256 reporterMask = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveBorrow)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveRepay)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);
        bureau.setReporterPermissions(address(adapter), reporterMask);
    }

    function test_ReconstructedPublishedFactsCreateOnlyNarrowSelfRepaymentObservation() public {
        assertEq(adapter.ETHEREUM_MAINNET_CHAIN_KEY(), CHAIN_KEY);
        assertEq(adapter.AAVE_V3_POOL(), AAVE_POOL);
        assertEq(adapter.USDC(), USDC);
        assertEq(adapter.MINIMUM_SELF_REPAYMENT_BLOCK_GAP(), 32);
        assertEq(REAL_REPAY_BLOCK - REAL_BORROW_BLOCK, 40);
        assertEq(REAL_BORROW_TX_INDEX, 201);
        assertEq(REAL_REPAY_TX_INDEX, 120);
        assertEq(REAL_BORROW_RECEIPT_LOG_ORDINAL, 4);
        assertEq(REAL_REPAY_RECEIPT_LOG_ORDINAL, 4);
        assertTrue(REAL_BORROW_TX != bytes32(0));
        assertTrue(REAL_REPAY_TX != bytes32(0));

        bytes32 borrowFactId =
            _ingestBorrow(REAL_BORROW_BLOCK, REAL_WALLET, REAL_WALLET, REAL_BORROW_AMOUNT, AAVE_POOL, USDC);
        bytes32 repayFactId =
            _ingestRepay(REAL_REPAY_BLOCK, REAL_WALLET, REAL_WALLET, REAL_REPAY_AMOUNT, false, AAVE_POOL, USDC);

        vm.prank(OTHER);
        bytes32 observationId = adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
        AaveEvidenceAdapter.SelfRepaymentObservation memory observation = adapter.observationOf(observationId);
        assertEq(observation.subject, REAL_WALLET);
        assertEq(observation.borrowFactId, borrowFactId);
        assertEq(observation.repayFactId, repayFactId);
        assertEq(observation.matchedAmount, REAL_BORROW_AMOUNT);
        assertEq(observation.sourceBlockGap, 40);

        PolicyV1.Profile memory profile = bureau.profileOf(REAL_WALLET);
        assertEq(profile.aaveBorrowFacts, 1);
        assertEq(profile.aaveRepayFacts, 1);
        assertEq(profile.aaveSelfRepaymentObservations, 1);
        assertEq(profile.largestObservedBorrowUsdc, REAL_BORROW_AMOUNT);
        assertEq(bureau.termsOf(REAL_WALLET).collateralBps, 14_500);
        assertEq(bureau.termsOf(REAL_WALLET).maxBorrowUsdc, 1_000e6);
    }

    function test_BorrowAttributionUsesOnBehalfOfNotUserOrTransactionSender() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, BORROW_USER, 12_345e6);
        bytes memory encoded = _encodedReceipt(logs, 1, OTHER);

        bytes32 factId = _ingestEncoded(100, encoded, 0);
        AaveEvidenceAdapter.AaveFact memory fact = adapter.factOf(factId);
        assertEq(uint256(fact.kind), uint256(AaveEvidenceAdapter.FactKind.BORROW));
        assertEq(fact.subject, SUBJECT);
        assertEq(fact.actor, BORROW_USER);
        assertEq(fact.reserve, USDC);
        assertEq(fact.amount, 12_345e6);
        assertEq(fact.interestRateMode, 2);
        assertFalse(fact.useATokens);

        PolicyV1.Profile memory subjectProfile = bureau.profileOf(SUBJECT);
        PolicyV1.Profile memory actorProfile = bureau.profileOf(BORROW_USER);
        PolicyV1.Profile memory senderProfile = bureau.profileOf(OTHER);
        assertEq(subjectProfile.aaveBorrowFacts, 1);
        assertEq(actorProfile.aaveBorrowFacts, 0);
        assertEq(senderProfile.aaveBorrowFacts, 0);
    }

    function test_RepayAttributionSeparatesDebtSubjectFromThirdPartyRepayer() public {
        bytes32 factId = _ingestRepay(200, SUBJECT, THIRD_PARTY, 8_000e6, true, AAVE_POOL, USDC);
        AaveEvidenceAdapter.AaveFact memory fact = adapter.factOf(factId);
        assertEq(uint256(fact.kind), uint256(AaveEvidenceAdapter.FactKind.REPAY));
        assertEq(fact.subject, SUBJECT);
        assertEq(fact.actor, THIRD_PARTY);
        assertEq(fact.amount, 8_000e6);
        assertTrue(fact.useATokens);

        assertEq(bureau.profileOf(SUBJECT).aaveRepayFacts, 1);
        assertEq(bureau.profileOf(THIRD_PARTY).aaveRepayFacts, 0);
    }

    function test_ExactReceiptOrdinalsProduceDistinctReplaySafeFacts() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        logs[1] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);

        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(300, encoded);
        bytes32 firstFactId = adapter.ingestAaveFact(context, inclusion, 0);
        bytes32 secondFactId = adapter.ingestAaveFact(context, inclusion, 1);
        assertTrue(firstFactId != secondFactId);
        assertEq(adapter.factOf(firstFactId).receiptLogOrdinal, 0);
        assertEq(adapter.factOf(secondFactId).receiptLogOrdinal, 1);
        assertEq(bureau.profileOf(SUBJECT).aaveBorrowFacts, 2);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.FactAlreadyRecorded.selector, firstFactId));
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsWrongEmitterAtExactOrdinal() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = _borrowLog(OTHER, USDC, SUBJECT, SUBJECT, 1_000e6);
        logs[1] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(400, encoded);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.WrongEmitter.selector, AAVE_POOL, OTHER));
        adapter.ingestAaveFact(context, inclusion, 0);

        bytes32 validFactId = adapter.ingestAaveFact(context, inclusion, 1);
        assertEq(adapter.factOf(validFactId).subject, SUBJECT);
    }

    function test_RejectsWrongTopicAtExactOrdinal() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        logs[0].topics[0] = keccak256("NotAaveBorrow()");
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(401, encoded);

        vm.expectRevert(
            abi.encodeWithSelector(AaveEvidenceAdapter.UnsupportedAaveEvent.selector, keccak256("NotAaveBorrow()"))
        );
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsMalformedEventData() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _repayLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6, false);
        logs[0].data = abi.encode(uint256(1_000e6));
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(402, encoded);

        vm.expectRevert(
            abi.encodeWithSelector(
                AaveEvidenceAdapter.MalformedEvent.selector, adapter.AAVE_REPAY(), uint256(4), uint256(32)
            )
        );
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsMalformedTopicCount() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        bytes32[] memory shortTopics = new bytes32[](3);
        for (uint256 i; i < shortTopics.length; ++i) {
            shortTopics[i] = logs[0].topics[i];
        }
        logs[0].topics = shortTopics;
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(403, encoded);

        vm.expectRevert(
            abi.encodeWithSelector(
                AaveEvidenceAdapter.MalformedEvent.selector, adapter.AAVE_BORROW(), uint256(3), uint256(128)
            )
        );
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsNonUsdcReserve() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, weth, SUBJECT, SUBJECT, 1 ether);
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(404, encoded);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.UnsupportedReserve.selector, weth));
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsUnsupportedBorrowInterestRateMode() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        logs[0].data = abi.encode(SUBJECT, uint256(1_000e6), uint8(3), uint256(4e25));
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(404, encoded);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.UnsupportedInterestRateMode.selector, uint8(3)));
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsFailedReceipt() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        bytes memory encoded = _encodedReceipt(logs, 0, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(405, encoded);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.SourceTransactionReverted.selector, uint8(0)));
        adapter.ingestAaveFact(context, inclusion, 0);
    }

    function test_RejectsWrongSourceChainBeforeVerification() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(AAVE_POOL, USDC, SUBJECT, SUBJECT, 1_000e6);
        bytes memory encoded = _encodedReceipt(logs, 1, SUBJECT);
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(406, encoded);
        context.chainKey = 2;

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.WrongSourceChain.selector, uint64(3), uint64(2)));
        adapter.ingestAaveFact(context, inclusion, 0);
        assertEq(verifier.verificationCalls(), 0);
    }

    function test_ThirdPartyRepaymentCannotBecomeSelfRepaymentObservation() public {
        bytes32 borrowFactId = _ingestBorrow(500, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(532, SUBJECT, THIRD_PARTY, 5_100e6, false, AAVE_POOL, USDC);

        vm.expectRevert(
            abi.encodeWithSelector(AaveEvidenceAdapter.RepaymentNotSelfFunded.selector, SUBJECT, THIRD_PARTY)
        );
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_RepaymentMustFollowBorrow() public {
        bytes32 borrowFactId = _ingestBorrow(600, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(599, SUBJECT, SUBJECT, 5_100e6, false, AAVE_POOL, USDC);

        vm.expectRevert(
            abi.encodeWithSelector(AaveEvidenceAdapter.RepaymentNotAfterBorrow.selector, uint64(600), uint64(599))
        );
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_RepaymentMustBeAtLeast32SourceBlocksLater() public {
        bytes32 borrowFactId = _ingestBorrow(700, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(731, SUBJECT, SUBJECT, 5_100e6, false, AAVE_POOL, USDC);

        vm.expectRevert(
            abi.encodeWithSelector(AaveEvidenceAdapter.SourceBlockGapTooSmall.selector, uint64(32), uint64(31))
        );
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_RepaymentAmountMustCoverReferencedBorrowAmount() public {
        bytes32 borrowFactId = _ingestBorrow(800, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(832, SUBJECT, SUBJECT, 4_999e6, false, AAVE_POOL, USDC);

        vm.expectRevert(
            abi.encodeWithSelector(
                AaveEvidenceAdapter.RepaymentAmountTooSmall.selector, uint128(5_000e6), uint128(4_999e6)
            )
        );
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_ObservationCannotReuseEitherFact() public {
        bytes32 borrowFactId = _ingestBorrow(900, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(932, SUBJECT, SUBJECT, 5_100e6, false, AAVE_POOL, USDC);
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.FactAlreadyUsed.selector, borrowFactId));
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_ObservationRequiresSameSubject() public {
        bytes32 borrowFactId = _ingestBorrow(1_000, SUBJECT, SUBJECT, 5_000e6, AAVE_POOL, USDC);
        bytes32 repayFactId = _ingestRepay(1_032, OTHER, OTHER, 5_100e6, false, AAVE_POOL, USDC);

        vm.expectRevert(abi.encodeWithSelector(AaveEvidenceAdapter.SubjectMismatch.selector, SUBJECT, OTHER));
        adapter.linkVerifiedSelfRepayment(borrowFactId, repayFactId);
    }

    function test_ConstructorRejectsZeroBureau() public {
        vm.expectRevert(AaveEvidenceAdapter.ZeroAddress.selector);
        new AaveEvidenceAdapter(verifier, PerformanceBureau(address(0)));
    }

    function test_ProductionAdapterPinsCreditcoinNativeVerifier() public {
        NativeAaveEvidenceAdapter nativeAdapter = new NativeAaveEvidenceAdapter(bureau);
        assertEq(address(nativeAdapter.VERIFIER()), 0x0000000000000000000000000000000000000FD2);
        assertEq(address(nativeAdapter.PERFORMANCE_BUREAU()), address(bureau));
    }

    function _ingestBorrow(
        uint64 blockHeight,
        address subject,
        address user,
        uint256 amount,
        address emitter,
        address reserve
    ) private returns (bytes32) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _borrowLog(emitter, reserve, subject, user, amount);
        return _ingestEncoded(blockHeight, _encodedReceipt(logs, 1, user), 0);
    }

    function _ingestRepay(
        uint64 blockHeight,
        address subject,
        address repayer,
        uint256 amount,
        bool useATokens,
        address emitter,
        address reserve
    ) private returns (bytes32) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = _repayLog(emitter, reserve, subject, repayer, amount, useATokens);
        return _ingestEncoded(blockHeight, _encodedReceipt(logs, 1, repayer), 0);
    }

    function _ingestEncoded(uint64 blockHeight, bytes memory encoded, uint256 ordinal) private returns (bytes32) {
        (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        ) = _prepare(blockHeight, encoded);
        return adapter.ingestAaveFact(context, inclusion, ordinal);
    }

    function _borrowLog(address emitter, address reserve, address subject, address user, uint256 amount)
        private
        pure
        returns (EvmV1Decoder.LogEntryTuple memory logEntry)
    {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = keccak256("Borrow(address,address,address,uint256,uint8,uint256,uint16)");
        topics[1] = _addressTopic(reserve);
        topics[2] = _addressTopic(subject);
        topics[3] = bytes32(0);
        logEntry = EvmV1Decoder.LogEntryTuple({
            address_: emitter, topics: topics, data: abi.encode(user, amount, uint8(2), uint256(4e25))
        });
    }

    function _repayLog(
        address emitter,
        address reserve,
        address subject,
        address repayer,
        uint256 amount,
        bool useATokens
    ) private pure returns (EvmV1Decoder.LogEntryTuple memory logEntry) {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = keccak256("Repay(address,address,address,uint256,bool)");
        topics[1] = _addressTopic(reserve);
        topics[2] = _addressTopic(subject);
        topics[3] = _addressTopic(repayer);
        logEntry =
            EvmV1Decoder.LogEntryTuple({ address_: emitter, topics: topics, data: abi.encode(amount, useATokens) });
    }

    function _encodedReceipt(EvmV1Decoder.LogEntryTuple[] memory logs, uint8 status, address from)
        private
        pure
        returns (bytes memory encoded)
    {
        bytes[] memory chunks = new bytes[](3);
        chunks[0] = abi.encode(uint64(1), uint64(500_000), from, false, AAVE_POOL, uint256(0), bytes(""));

        EvmV1Decoder.AccessListEntryBytes32[] memory accessList = new EvmV1Decoder.AccessListEntryBytes32[](0);
        chunks[1] = abi.encode(
            uint64(1), uint128(1 gwei), uint128(30 gwei), accessList, uint8(0), bytes32(uint256(1)), bytes32(uint256(2))
        );
        chunks[2] = abi.encode(status, uint64(250_000), logs, bytes(""));
        encoded = abi.encode(uint8(2), chunks);
    }

    function _prepare(uint64 blockHeight, bytes memory encoded)
        private
        returns (
            AttestcoinProofAdapter.BlockContext memory context,
            AttestcoinProofAdapter.TransactionInclusion memory inclusion
        )
    {
        context.chainKey = CHAIN_KEY;
        context.blockHeight = blockHeight;
        context.lowerEndpointDigest = keccak256(abi.encode("aave-lower-endpoint", blockHeight));
        context.continuityRoots = new bytes32[](1);
        context.continuityRoots[0] = keccak256(abi.encode("aave-continuity", blockHeight));

        inclusion.encodedTransaction = encoded;
        inclusion.merkleRoot = keccak256(abi.encode("aave-test-root", blockHeight, encoded));
        inclusion.siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        inclusion.siblings[0] = INativeQueryVerifier.MerkleProofEntry({ hash: keccak256("sibling"), isLeft: false });

        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({ root: inclusion.merkleRoot, siblings: inclusion.siblings });
        INativeQueryVerifier.ContinuityProof memory continuityProof = INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: context.lowerEndpointDigest, roots: context.continuityRoots
        });
        verifier.allowProof(CHAIN_KEY, blockHeight, encoded, merkleProof, continuityProof);
    }

    function _addressTopic(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}
