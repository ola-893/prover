// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { PolicyV1 } from "../src/PolicyV1.sol";
import { TestBase } from "./TestBase.sol";

contract PerformanceBureauTest is TestBase {
    PerformanceBureau internal bureau;

    address internal constant REPORTER = address(0xA11CE);
    address internal constant OTHER_REPORTER = address(0xB0B);
    address internal constant SUBJECT = address(0xCAFE);

    function setUp() public {
        bureau = new PerformanceBureau();
    }

    function test_OnlyOwnerCanSetReporterPermissions() public {
        vm.prank(OTHER_REPORTER);
        vm.expectRevert(abi.encodeWithSelector(PerformanceBureau.NotOwner.selector, OTHER_REPORTER));
        bureau.setReporterPermissions(REPORTER, type(uint256).max);

        uint256 cyclePermission = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveCycle);
        bureau.setReporterPermissions(REPORTER, cyclePermission);
        assertEq(bureau.reporterPermissions(REPORTER), cyclePermission);
    }

    function test_ReporterPermissionIsScopedByEvidenceKind() public {
        uint256 cyclePermission = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveCycle);
        bureau.setReporterPermissions(REPORTER, cyclePermission);

        vm.prank(REPORTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                PerformanceBureau.UnauthorizedReporter.selector, REPORTER, PerformanceBureau.EvidenceKind.SandwichBreach
            )
        );
        bureau.recordEvidence(
            SUBJECT, bytes32(uint256(1)), PerformanceBureau.EvidenceKind.SandwichBreach, 10 ether, false
        );
    }

    function test_EvidenceCanOnlyUpdateAProfileOnce() public {
        _permit(REPORTER, PerformanceBureau.EvidenceKind.AaveCycle);
        bytes32 evidenceId = keccak256("one-cycle");

        vm.prank(REPORTER);
        bureau.recordEvidence(SUBJECT, evidenceId, PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);

        vm.prank(REPORTER);
        vm.expectRevert(abi.encodeWithSelector(PerformanceBureau.EvidenceAlreadyRecorded.selector, evidenceId));
        bureau.recordEvidence(SUBJECT, evidenceId, PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);

        PolicyV1.Profile memory profile = bureau.profileOf(SUBJECT);
        assertEq(profile.matchedAaveCycles, 1);
        assertEq(profile.maxMatchedUsdc, 4_000e6);
    }

    function test_ProfileUpdatesAreKindSpecificAndRepriceTerms() public {
        uint256 mask = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveBorrow)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveRepay)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveCycle)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.FifoBreach);
        bureau.setReporterPermissions(REPORTER, mask);

        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveBorrow, 4_000e6, false);
        _record(bytes32(uint256(2)), PerformanceBureau.EvidenceKind.AaveRepay, 4_100e6, false);
        _record(bytes32(uint256(3)), PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);

        PolicyV1.Profile memory afterCycle = bureau.profileOf(SUBJECT);
        PolicyV1.Terms memory cycleTerms = bureau.termsOf(SUBJECT);
        assertEq(afterCycle.aaveBorrowFacts, 1);
        assertEq(afterCycle.aaveRepayFacts, 1);
        assertEq(afterCycle.matchedAaveCycles, 1);
        assertEq(cycleTerms.collateralBps, 14_000);
        assertEq(cycleTerms.maxBorrowUsdc, 1_100e6);

        _record(bytes32(uint256(4)), PerformanceBureau.EvidenceKind.SandwichBreach, 10 ether, false);
        _record(bytes32(uint256(5)), PerformanceBureau.EvidenceKind.FifoBreach, 0, true);

        PolicyV1.Profile memory afterBreaches = bureau.profileOf(SUBJECT);
        PolicyV1.Terms memory breachTerms = bureau.termsOf(SUBJECT);
        assertEq(afterBreaches.sandwichBreaches, 1);
        assertEq(afterBreaches.fifoBreaches, 1);
        assertEq(afterBreaches.uncompensatedBreaches, 1);
        assertEq(afterBreaches.totalSlashedCtc, 10 ether);
        assertEq(breachTerms.collateralBps, 15_000);
        assertEq(breachTerms.premiumBps, 350);
        assertEq(breachTerms.minimumBondCtc, 250 ether);
        assertEq(breachTerms.maxBorrowUsdc, 880e6);
    }

    function test_LowerLaterCycleDoesNotReduceDemonstratedCapacity() public {
        _permit(REPORTER, PerformanceBureau.EvidenceKind.AaveCycle);
        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);
        _record(bytes32(uint256(2)), PerformanceBureau.EvidenceKind.AaveCycle, 500e6, false);

        PolicyV1.Profile memory profile = bureau.profileOf(SUBJECT);
        assertEq(profile.matchedAaveCycles, 2);
        assertEq(profile.maxMatchedUsdc, 4_000e6);
        assertEq(bureau.termsOf(SUBJECT).collateralBps, 13_000);
    }

    function test_UncompensatedFlagOnlyAppliesToBreaches() public {
        _permit(REPORTER, PerformanceBureau.EvidenceKind.AaveRepay);

        vm.prank(REPORTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                PerformanceBureau.InvalidUncompensatedFlag.selector, PerformanceBureau.EvidenceKind.AaveRepay
            )
        );
        bureau.recordEvidence(SUBJECT, bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveRepay, 1_000e6, true);
    }

    function _permit(address reporter, PerformanceBureau.EvidenceKind kind) private {
        bureau.setReporterPermissions(reporter, bureau.permissionFor(kind));
    }

    function _record(bytes32 evidenceId, PerformanceBureau.EvidenceKind kind, uint128 value, bool uncompensated)
        private
    {
        vm.prank(REPORTER);
        bureau.recordEvidence(SUBJECT, evidenceId, kind, value, uncompensated);
    }
}

