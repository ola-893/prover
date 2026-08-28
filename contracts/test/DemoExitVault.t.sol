// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { DemoExitVault } from "../src/DemoExitVault.sol";
import { TestBase, Vm } from "./TestBase.sol";

contract DemoExitVaultTest is TestBase {
    DemoExitVault internal vault;

    address internal constant OPERATOR = address(0xA11CE);
    address internal constant ALICE = address(0xA11);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        vault = new DemoExitVault(OPERATOR);
    }

    function test_RequestIdsAreMonotonicAndBoundToCaller() public {
        vm.prank(ALICE);
        uint256 first = vault.requestExit(100);
        vm.prank(BOB);
        uint256 second = vault.requestExit(200);

        assertEq(first, 1);
        assertEq(second, 2);
        DemoExitVault.ExitRequest memory firstRequest = vault.requestOf(first);
        DemoExitVault.ExitRequest memory secondRequest = vault.requestOf(second);
        assertEq(firstRequest.owner, ALICE);
        assertEq(firstRequest.shares, 100);
        assertEq(secondRequest.owner, BOB);
        assertEq(secondRequest.shares, 200);
    }

    function test_OnlyOperatorCanProcessExit() public {
        vm.prank(ALICE);
        uint256 requestId = vault.requestExit(100);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(DemoExitVault.NotOperator.selector, ALICE));
        vault.processExit(requestId, 90);
    }

    function test_OperatorCanCreateObservableCompletedFifoInversion() public {
        vm.prank(ALICE);
        uint256 first = vault.requestExit(100);
        vm.prank(BOB);
        uint256 second = vault.requestExit(200);

        // Deliberately process request 2 before request 1. A future OrderingCourt will prove
        // this positive four-transaction contradiction without relying on non-inclusion.
        vm.prank(OPERATOR);
        vault.processExit(second, 180);
        vm.prank(OPERATOR);
        vault.processExit(first, 90);

        DemoExitVault.ExitRequest memory firstRequest = vault.requestOf(first);
        DemoExitVault.ExitRequest memory secondRequest = vault.requestOf(second);
        assertTrue(firstRequest.processed);
        assertTrue(secondRequest.processed);
        assertEq(firstRequest.assets, 90);
        assertEq(secondRequest.assets, 180);
    }

    function test_RequestAndProcessEventsCarryCourtDecodableFacts() public {
        vm.recordLogs();
        vm.prank(ALICE);
        uint256 requestId = vault.requestExit(100);
        vm.prank(OPERATOR);
        vault.processExit(requestId, 90);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);

        assertEq(logs[0].emitter, address(vault));
        assertEq(logs[0].topics[0], keccak256("ExitRequested(uint256,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(requestId));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), 100);

        assertEq(logs[1].emitter, address(vault));
        assertEq(logs[1].topics[0], keccak256("ExitProcessed(uint256,address,uint256)"));
        assertEq(logs[1].topics[1], bytes32(requestId));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[1].data, (uint256)), 90);
    }

    function test_RequestCannotBeProcessedTwice() public {
        vm.prank(ALICE);
        uint256 requestId = vault.requestExit(100);
        vm.prank(OPERATOR);
        vault.processExit(requestId, 90);

        vm.prank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(DemoExitVault.RequestAlreadyProcessed.selector, requestId));
        vault.processExit(requestId, 90);
    }
}
