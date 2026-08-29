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

        uint256 observationPermission =
            bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);
        bureau.setReporterPermissions(REPORTER, observationPermission);
        assertEq(bureau.reporterPermissions(REPORTER), observationPermission);
    }

    function test_ReporterPermissionIsScopedByEvidenceKind() public {
        uint256 observationPermission =
            bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);
        bureau.setReporterPermissions(REPORTER, observationPermission);

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
        _permit(REPORTER, PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);
        bytes32 evidenceId = keccak256("one-self-repayment-observation");

        vm.prank(REPORTER);
        bureau.recordEvidence(
            SUBJECT, evidenceId, PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 4_000e6, false
        );

        vm.prank(REPORTER);
        vm.expectRevert(abi.encodeWithSelector(PerformanceBureau.EvidenceAlreadyRecorded.selector, evidenceId));
        bureau.recordEvidence(
            SUBJECT, evidenceId, PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 4_000e6, false
        );

        PolicyV1.Profile memory profile = bureau.profileOf(SUBJECT);
        assertEq(profile.aaveSelfRepaymentObservations, 1);
        assertEq(profile.largestObservedBorrowUsdc, 4_000e6);
    }

    function test_ProfileUpdatesAreKindSpecificAndRepriceTerms() public {
        uint256 mask = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveBorrow)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveRepay)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.FifoBreach);
        bureau.setReporterPermissions(REPORTER, mask);

        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveBorrow, 4_000e6, false);
        _record(bytes32(uint256(2)), PerformanceBureau.EvidenceKind.AaveRepay, 4_100e6, false);
        _record(bytes32(uint256(3)), PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 4_000e6, false);

        PolicyV1.Profile memory afterObservation = bureau.profileOf(SUBJECT);
        PolicyV1.Terms memory observationTerms = bureau.termsOf(SUBJECT);
        assertEq(afterObservation.aaveBorrowFacts, 1);
        assertEq(afterObservation.aaveRepayFacts, 1);
        assertEq(afterObservation.aaveSelfRepaymentObservations, 1);
        assertEq(observationTerms.collateralBps, 14_500);
        assertEq(observationTerms.maxBorrowUsdc, 140e6);

        _record(bytes32(uint256(4)), PerformanceBureau.EvidenceKind.SandwichBreach, 10 ether, false);
        _record(bytes32(uint256(5)), PerformanceBureau.EvidenceKind.FifoBreach, 0, true);

        PolicyV1.Profile memory afterBreaches = bureau.profileOf(SUBJECT);
        PolicyV1.Terms memory breachTerms = bureau.termsOf(SUBJECT);
        assertEq(afterBreaches.sandwichBreaches, 1);
        assertEq(afterBreaches.fifoBreaches, 1);
        assertEq(afterBreaches.uncompensatedBreaches, 1);
        assertEq(afterBreaches.totalSlashedCtc, 10 ether);
        assertEq(breachTerms.collateralBps, 15_500);
        assertEq(breachTerms.premiumBps, 350);
        assertEq(breachTerms.minimumBondCtc, 250 ether);
        assertEq(breachTerms.maxBorrowUsdc, 112e6);
    }

    function test_LowerLaterObservationDoesNotReduceDemonstratedCapacityOrStackDiscount() public {
        _permit(REPORTER, PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);
        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 4_000e6, false);
        _record(bytes32(uint256(2)), PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation, 500e6, false);

        PolicyV1.Profile memory profile = bureau.profileOf(SUBJECT);
        assertEq(profile.aaveSelfRepaymentObservations, 2);
        assertEq(profile.largestObservedBorrowUsdc, 4_000e6);
        assertEq(bureau.termsOf(SUBJECT).collateralBps, 14_500);
        assertEq(bureau.termsOf(SUBJECT).maxBorrowUsdc, 140e6);
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
