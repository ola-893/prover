// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PromiseSourceRegistry } from "../src/PromiseSourceRegistry.sol";
import { TestBase } from "./TestBase.sol";

contract PromiseSourceRegistryTest is TestBase {
    address private constant GOVERNOR = address(0x600D);
    address private constant NEXT_GOVERNOR = address(0xBEEF);
    address private constant SOURCE = address(0x5150);
    address private constant OTHER = address(0xBAD);
    uint64 private constant CHAIN_KEY = 3;
    bytes32 private constant POLICY_ID = keccak256("PROVER_PROMISE_RFQ_EXECUTED_V1");

    PromiseSourceRegistry private registry;

    function setUp() public {
        registry = new PromiseSourceRegistry(GOVERNOR);
    }

    function test_OnlyGovernorCanApproveAndApprovalIsExact() public {
        bytes32 expected = registry.sourceKey(0, CHAIN_KEY, SOURCE, POLICY_ID);

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(PromiseSourceRegistry.NotGovernor.selector, OTHER));
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);

        vm.prank(GOVERNOR);
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);
        (bytes32 key, PromiseSourceRegistry.Approval memory approval) =
            registry.approvalOf(0, CHAIN_KEY, SOURCE, POLICY_ID);
        assertEq(key, expected);
        assertEq(approval.revision, 1);
        assertTrue(approval.approved);

        (, PromiseSourceRegistry.Approval memory wrongKind) = registry.approvalOf(1, CHAIN_KEY, SOURCE, POLICY_ID);
        (, PromiseSourceRegistry.Approval memory wrongChain) = registry.approvalOf(0, CHAIN_KEY + 1, SOURCE, POLICY_ID);
        (, PromiseSourceRegistry.Approval memory wrongSource) = registry.approvalOf(0, CHAIN_KEY, OTHER, POLICY_ID);
        (, PromiseSourceRegistry.Approval memory wrongPolicy) =
            registry.approvalOf(0, CHAIN_KEY, SOURCE, keccak256("other-policy"));
        assertFalse(wrongKind.approved);
        assertFalse(wrongChain.approved);
        assertFalse(wrongSource.approved);
        assertFalse(wrongPolicy.approved);
    }

    function test_EveryToggleIncrementsRevisionAndUnchangedStatusReverts() public {
        vm.startPrank(GOVERNOR);
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);
        bytes32 key = registry.sourceKey(0, CHAIN_KEY, SOURCE, POLICY_ID);
        vm.expectRevert(abi.encodeWithSelector(PromiseSourceRegistry.SourceApprovalUnchanged.selector, key, true));
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);

        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, false);
        (, PromiseSourceRegistry.Approval memory revoked) = registry.approvalOf(0, CHAIN_KEY, SOURCE, POLICY_ID);
        assertEq(revoked.revision, 2);
        assertFalse(revoked.approved);

        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);
        vm.stopPrank();
        (, PromiseSourceRegistry.Approval memory restored) = registry.approvalOf(0, CHAIN_KEY, SOURCE, POLICY_ID);
        assertEq(restored.revision, 3);
        assertTrue(restored.approved);
    }

    function test_RejectsZeroSourceAndPolicy() public {
        vm.prank(GOVERNOR);
        vm.expectRevert(PromiseSourceRegistry.ZeroAddress.selector);
        registry.setSourceApproval(0, CHAIN_KEY, address(0), POLICY_ID, true);

        vm.prank(GOVERNOR);
        vm.expectRevert(PromiseSourceRegistry.ZeroPolicyId.selector);
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, bytes32(0), true);
    }

    function test_GovernanceTransferRequiresPendingGovernorAcceptance() public {
        vm.prank(GOVERNOR);
        registry.beginGovernanceTransfer(NEXT_GOVERNOR);
        assertEq(registry.pendingGovernor(), NEXT_GOVERNOR);

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(PromiseSourceRegistry.NotPendingGovernor.selector, OTHER));
        registry.acceptGovernance();

        vm.prank(NEXT_GOVERNOR);
        registry.acceptGovernance();
        assertEq(registry.governor(), NEXT_GOVERNOR);
        assertEq(registry.pendingGovernor(), address(0));

        vm.prank(GOVERNOR);
        vm.expectRevert(abi.encodeWithSelector(PromiseSourceRegistry.NotGovernor.selector, GOVERNOR));
        registry.setSourceApproval(0, CHAIN_KEY, SOURCE, POLICY_ID, true);
    }
}
