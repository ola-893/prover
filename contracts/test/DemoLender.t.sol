// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { DemoLender } from "../src/DemoLender.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { PolicyV1 } from "../src/PolicyV1.sol";
import { TestBase } from "./TestBase.sol";

contract DemoLenderTest is TestBase {
    PerformanceBureau internal bureau;
    DemoLender internal lender;

    address internal constant REPORTER = address(0xA11CE);
    address internal constant BORROWER = address(0xB0B);
    address internal constant STRANGER = address(0xBAD);

    function setUp() public {
        bureau = new PerformanceBureau();
        lender = new DemoLender(address(bureau));
        uint256 mask = bureau.permissionFor(PerformanceBureau.EvidenceKind.AaveCycle)
            | bureau.permissionFor(PerformanceBureau.EvidenceKind.SandwichBreach);
        bureau.setReporterPermissions(REPORTER, mask);
    }

    function test_VerifiedCycleProducesBetterCollateralQuote() public {
        (PolicyV1.Terms memory beforeTerms,) = lender.quote(BORROWER, 100e6);
        assertEq(beforeTerms.collateralBps, 15_000);

        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);

        (PolicyV1.Terms memory afterTerms, uint128 requiredCollateral) = lender.quote(BORROWER, 1_000e6);
        assertEq(afterTerms.collateralBps, 14_000);
        assertEq(afterTerms.maxBorrowUsdc, 1_100e6);
        assertEq(requiredCollateral, 1_400 ether);
    }

    function test_OnlyLenderOwnerCanCreateOffer() public {
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(DemoLender.NotOwner.selector, STRANGER));
        lender.makeOffer(BORROWER, 100e6, 7 days);
    }

    function test_OfferFreezesTermsAtOrigination() public {
        _record(bytes32(uint256(1)), PerformanceBureau.EvidenceKind.AaveCycle, 4_000e6, false);
        vm.warp(1_000_000);
        bytes32 offerId = lender.makeOffer(BORROWER, 1_000e6, 7 days);

        _record(bytes32(uint256(2)), PerformanceBureau.EvidenceKind.SandwichBreach, 10 ether, false);

        DemoLender.Offer memory offer = lender.offerOf(offerId);
        PolicyV1.Terms memory current = bureau.termsOf(BORROWER);
        assertEq(offer.borrower, BORROWER);
        assertEq(offer.principalUsdc, 1_000e6);
        assertEq(offer.requiredCollateralCtc, 1_400 ether);
        assertEq(offer.terms.collateralBps, 14_000);
        assertEq(offer.expiresAt, 1_000_000 + 7 days);
        assertEq(current.collateralBps, 14_500);
        assertEq(current.premiumBps, 150);
    }

    function test_QuoteRejectsAmountAboveCurrentLimit() public {
        vm.expectRevert(abi.encodeWithSelector(DemoLender.ExceedsBorrowLimit.selector, 101e6, 100e6));
        lender.quote(BORROWER, 101e6);
    }

    function _record(bytes32 evidenceId, PerformanceBureau.EvidenceKind kind, uint128 value, bool uncompensated)
        private
    {
        vm.prank(REPORTER);
        bureau.recordEvidence(BORROWER, evidenceId, kind, value, uncompensated);
    }
}

