// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { OrderingPredicates } from "../src/attestcoin/OrderingPredicates.sol";
import { TestBase } from "./TestBase.sol";

contract OrderingPredicatesHarness {
    function isBefore(OrderingPredicates.Position calldata left, OrderingPredicates.Position calldata right)
        external
        pure
        returns (bool)
    {
        return OrderingPredicates.isBefore(left, right);
    }

    function isImmediatelyBeforeInBlock(
        OrderingPredicates.Position calldata left,
        OrderingPredicates.Position calldata right
    ) external pure returns (bool) {
        return OrderingPredicates.isImmediatelyBeforeInBlock(left, right);
    }

    function assertBefore(OrderingPredicates.Position calldata left, OrderingPredicates.Position calldata right)
        external
        pure
    {
        OrderingPredicates.assertBefore(left, right);
    }

    function assertStrictlyAscending(OrderingPredicates.Position[] calldata positions) external pure {
        OrderingPredicates.assertStrictlyAscending(positions);
    }
}

contract OrderingPredicatesTest is TestBase {
    OrderingPredicatesHarness private harness;

    function setUp() public {
        harness = new OrderingPredicatesHarness();
    }

    function test_PositionOrderingCrossesBlockBoundaries() public view {
        OrderingPredicates.Position memory lastInEarlierBlock = _position(3, 100, 999);
        OrderingPredicates.Position memory firstInLaterBlock = _position(3, 101, 0);

        assertTrue(harness.isBefore(lastInEarlierBlock, firstInLaterBlock));
        assertFalse(harness.isBefore(firstInLaterBlock, lastInEarlierBlock));
        assertFalse(harness.isImmediatelyBeforeInBlock(lastInEarlierBlock, firstInLaterBlock));
    }

    function test_AdjacencyIsRecognizedOnlyInsideOneBlock() public view {
        assertTrue(harness.isImmediatelyBeforeInBlock(_position(3, 100, 14), _position(3, 100, 15)));
        assertFalse(harness.isImmediatelyBeforeInBlock(_position(3, 100, 14), _position(3, 100, 16)));
    }

    function test_DifferentSourceChainsAreIncomparable() public {
        vm.expectRevert(abi.encodeWithSelector(OrderingPredicates.DifferentSourceChains.selector, uint64(3), uint64(1)));
        harness.isBefore(_position(3, 100, 0), _position(1, 100, 1));
    }

    function test_EqualPositionIsNotBeforeItself() public {
        OrderingPredicates.Position memory position = _position(3, 100, 14);
        vm.expectRevert(
            abi.encodeWithSelector(OrderingPredicates.PositionNotBefore.selector, uint64(100), uint64(14), 100, 14)
        );
        harness.assertBefore(position, position);
    }

    function test_StrictSequenceRejectsAnInversion() public {
        OrderingPredicates.Position[] memory positions = new OrderingPredicates.Position[](3);
        positions[0] = _position(3, 100, 14);
        positions[1] = _position(3, 100, 16);
        positions[2] = _position(3, 100, 15);

        vm.expectRevert(abi.encodeWithSelector(OrderingPredicates.SequenceNotAscending.selector, uint256(2)));
        harness.assertStrictlyAscending(positions);
    }

    function _position(uint64 chainKey, uint64 blockHeight, uint64 txIndex)
        private
        pure
        returns (OrderingPredicates.Position memory)
    {
        return OrderingPredicates.Position({ chainKey: chainKey, blockHeight: blockHeight, txIndex: txIndex });
    }
}
