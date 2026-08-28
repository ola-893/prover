// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CovenantBook, IAttestedHeightSource } from "../src/CovenantBook.sol";
import { TestBase } from "./TestBase.sol";

interface VmDeal {
    function deal(address account, uint256 newBalance) external;
}

contract MockAttestedHeightSource is IAttestedHeightSource {
    mapping(uint64 chainKey => HeightHashResult result) internal _tips;

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

contract CourtCaller {
    function settle(CovenantBook book, bytes32 covenantId, bytes32 evidenceId, uint64 breachHeight, address beneficiary)
        external
        returns (uint256 paid, uint256 shortfall)
    {
        return book.settleBreach(covenantId, evidenceId, breachHeight, beneficiary);
    }
}

contract PayoutReceiver {
    uint256 public received;

    function withdraw(CovenantBook book) external {
        book.withdrawPayout(payable(address(this)));
    }

    receive() external payable {
        received += msg.value;
    }
}

contract CovenantBookTest is TestBase {
    uint64 internal constant CHAIN_KEY = 1;
    uint64 internal constant INITIAL_TIP = 1_000;
    uint64 internal constant MIN_LEAD = 64;
    uint64 internal constant VALID_FROM = 1_100;
    uint64 internal constant VALID_UNTIL = 2_000;

    address internal constant OPERATOR = address(0xA11CE);
    address internal constant OTHER = address(0xBAD);
    address internal constant SOURCE = address(0x5150);
    bytes32 internal constant POLICY_HASH = keccak256("policy-v1");

    MockAttestedHeightSource internal chainInfo;
    CourtCaller internal sandwichCourt;
    CourtCaller internal fifoCourt;
    CovenantBook internal book;

    function setUp() public {
        chainInfo = new MockAttestedHeightSource();
        chainInfo.setTip(CHAIN_KEY, INITIAL_TIP, true);
        sandwichCourt = new CourtCaller();
        fifoCourt = new CourtCaller();
        book = new CovenantBook(address(chainInfo), address(sandwichCourt), address(fifoCourt));
        VmDeal(address(vm)).deal(OPERATOR, 1_000 ether);
    }

    function test_NoSandwichCovenantIsOperatorBoundWithExplicitFutureActivation() public {
        bytes32 covenantId = _openNoSandwich(30 ether, 10 ether);
        CovenantBook.Covenant memory covenant = book.covenantOf(covenantId);

        assertEq(covenant.operator, OPERATOR);
        assertEq(covenant.sourceContract, SOURCE);
        assertEq(covenant.policyHash, POLICY_HASH);
        assertEq(uint256(covenant.covenantType), uint256(CovenantBook.CovenantType.NO_SANDWICH));
        assertEq(covenant.chainKey, CHAIN_KEY);
        assertEq(covenant.validFromHeight, VALID_FROM);
        assertEq(covenant.validUntilHeight, VALID_UNTIL);
        assertEq(covenant.claimDeadlineHeight, VALID_UNTIL + book.CLAIM_WINDOW_BLOCKS());
        assertEq(covenant.fixedPenalty, 10 ether);
        assertEq(covenant.initialBond, 30 ether);
        assertEq(covenant.remainingBond, 30 ether);
        assertEq(book.MIN_ATTESTED_LEAD_BLOCKS(), MIN_LEAD);

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CovenantBook.ActivationLeadTooShort.selector, INITIAL_TIP + MIN_LEAD - 1, INITIAL_TIP + MIN_LEAD
            )
        );
        book.openNoSandwich{ value: 10 ether }(
            CHAIN_KEY, SOURCE, INITIAL_TIP + MIN_LEAD - 1, VALID_UNTIL, POLICY_HASH, 10 ether
        );

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(CovenantBook.CoverageEndsBeforeActivation.selector, VALID_FROM, VALID_FROM - 1)
        );
        book.openNoSandwich{ value: 10 ether }(CHAIN_KEY, SOURCE, VALID_FROM, VALID_FROM - 1, POLICY_HASH, 10 ether);
    }

    function test_FifoCovenantCanOnlyBeSettledByFifoCourt() public {
        bytes32 covenantId = _openFifo(20 ether, 10 ether);
        chainInfo.setTip(CHAIN_KEY, 1_500, true);

        vm.expectRevert(
            abi.encodeWithSelector(CovenantBook.WrongCourt.selector, address(sandwichCourt), address(fifoCourt))
        );
        sandwichCourt.settle(book, covenantId, keccak256("inversion"), 1_200, OTHER);

        (uint256 paid, uint256 shortfall) = fifoCourt.settle(book, covenantId, keccak256("inversion"), 1_200, OTHER);
        assertEq(paid, 10 ether);
        assertEq(shortfall, 0);
    }

    function test_BreachSettlementUsesFixedPenaltyAndRecordsBondExhaustion() public {
        bytes32 covenantId = _openNoSandwich(25 ether, 10 ether);
        chainInfo.setTip(CHAIN_KEY, 1_500, true);
        PayoutReceiver receiver = new PayoutReceiver();

        sandwichCourt.settle(book, covenantId, keccak256("breach-1"), 1_200, address(receiver));
        sandwichCourt.settle(book, covenantId, keccak256("breach-2"), 1_300, address(receiver));
        (uint256 paid, uint256 shortfall) =
            sandwichCourt.settle(book, covenantId, keccak256("breach-3"), 1_400, address(receiver));

        assertEq(paid, 5 ether);
        assertEq(shortfall, 5 ether);
        CovenantBook.Covenant memory covenant = book.covenantOf(covenantId);
        assertEq(covenant.breachCount, 3);
        assertEq(covenant.remainingBond, 0);
        assertEq(covenant.totalPaid, 25 ether);
        assertEq(covenant.totalShortfall, 5 ether);
        assertEq(book.claimable(address(receiver)), 25 ether);
        assertEq(receiver.received(), 0);

        receiver.withdraw(book);
        assertEq(receiver.received(), 25 ether);
        assertEq(book.claimable(address(receiver)), 0);
    }

    function test_ClaimReplayIsRejectedPerCovenant() public {
        bytes32 covenantId = _openNoSandwich(20 ether, 10 ether);
        chainInfo.setTip(CHAIN_KEY, 1_500, true);
        bytes32 evidenceId = keccak256("same-evidence");

        sandwichCourt.settle(book, covenantId, evidenceId, 1_200, OTHER);
        bytes32 claimKey = book.claimKeyFor(covenantId, evidenceId);
        assertTrue(book.settledClaims(claimKey));

        vm.expectRevert(abi.encodeWithSelector(CovenantBook.ClaimAlreadySettled.selector, claimKey));
        sandwichCourt.settle(book, covenantId, evidenceId, 1_200, OTHER);
    }

    function test_CourtCannotSettleOutsideCoverageOrAboveAttestedTip() public {
        bytes32 covenantId = _openNoSandwich(20 ether, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(CovenantBook.BreachOutsideCoverage.selector, INITIAL_TIP, VALID_FROM, VALID_UNTIL)
        );
        sandwichCourt.settle(book, covenantId, keccak256("too-early"), INITIAL_TIP, OTHER);

        vm.expectRevert(abi.encodeWithSelector(CovenantBook.BreachHeightNotAttested.selector, 1_200, INITIAL_TIP));
        sandwichCourt.settle(book, covenantId, keccak256("not-attested"), 1_200, OTHER);
    }

    function test_BondCannotBeReleasedBeforeSourceHeightClaimWindowCloses() public {
        bytes32 covenantId = _openNoSandwich(30 ether, 10 ether);
        uint64 deadline = VALID_UNTIL + book.CLAIM_WINDOW_BLOCKS();

        vm.prank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(CovenantBook.ClaimWindowStillOpen.selector, INITIAL_TIP, deadline));
        book.releaseMaturedBond(covenantId);

        chainInfo.setTip(CHAIN_KEY, deadline + 1, true);
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(CovenantBook.NotCovenantOperator.selector, OTHER, OPERATOR));
        book.releaseMaturedBond(covenantId);

        vm.prank(OPERATOR);
        book.releaseMaturedBond(covenantId);
        CovenantBook.Covenant memory covenant = book.covenantOf(covenantId);
        assertTrue(covenant.bondReleased);
        assertEq(covenant.remainingBond, 0);
        assertEq(book.claimable(OPERATOR), 30 ether);

        uint256 beforeBalance = OPERATOR.balance;
        vm.prank(OPERATOR);
        book.withdrawPayout(payable(OPERATOR));
        assertEq(OPERATOR.balance, beforeBalance + 30 ether);
    }

    function test_ClaimsCloseBeforeMaturedBondCanBeReleased() public {
        bytes32 covenantId = _openNoSandwich(30 ether, 10 ether);
        uint64 deadline = VALID_UNTIL + book.CLAIM_WINDOW_BLOCKS();
        chainInfo.setTip(CHAIN_KEY, deadline + 1, true);

        vm.expectRevert(abi.encodeWithSelector(CovenantBook.ClaimWindowClosed.selector, deadline + 1, deadline));
        sandwichCourt.settle(book, covenantId, keccak256("late-claim"), 1_200, OTHER);
    }

    function test_OpeningRequiresAnAttestedSourceAndEnoughBond() public {
        chainInfo.setTip(99, 0, false);
        vm.prank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(CovenantBook.SourceChainNotAttested.selector, uint64(99)));
        book.openFifo{ value: 10 ether }(99, SOURCE, VALID_FROM, VALID_UNTIL, POLICY_HASH, 10 ether);

        vm.prank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(CovenantBook.InsufficientInitialBond.selector, 9 ether, 10 ether));
        book.openFifo{ value: 9 ether }(CHAIN_KEY, SOURCE, VALID_FROM, VALID_UNTIL, POLICY_HASH, 10 ether);
    }

    function _openNoSandwich(uint256 bond, uint256 penalty) private returns (bytes32 covenantId) {
        vm.prank(OPERATOR);
        covenantId =
            book.openNoSandwich{ value: bond }(CHAIN_KEY, SOURCE, VALID_FROM, VALID_UNTIL, POLICY_HASH, penalty);
    }

    function _openFifo(uint256 bond, uint256 penalty) private returns (bytes32 covenantId) {
        vm.prank(OPERATOR);
        covenantId = book.openFifo{ value: bond }(CHAIN_KEY, SOURCE, VALID_FROM, VALID_UNTIL, POLICY_HASH, penalty);
    }
}
