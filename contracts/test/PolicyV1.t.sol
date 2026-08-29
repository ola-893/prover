// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PolicyV1 } from "../src/PolicyV1.sol";
import { TestBase } from "./TestBase.sol";

contract PolicyHarness {
    function quote(PolicyV1.Profile calldata profile) external pure returns (PolicyV1.Terms memory) {
        return PolicyV1.quote(profile);
    }
}

contract PolicyV1Test is TestBase {
    PolicyHarness internal policy;

    function setUp() public {
        policy = new PolicyHarness();
    }

    function test_BaselineTermsAreExplicit() public view {
        PolicyV1.Profile memory profile;
        PolicyV1.Terms memory terms = policy.quote(profile);

        assertEq(terms.collateralBps, 15_000);
        assertEq(terms.premiumBps, 50);
        assertEq(terms.bondMultiplierBps, 10_000);
        assertEq(terms.maxBorrowUsdc, 100e6);
        assertEq(terms.minimumBondCtc, 100 ether);
        assertEq(terms.reasonFlags, 0);
    }

    function test_ObservationBenefitIsConservativeAndCapsAtOneObservation() public view {
        PolicyV1.Profile memory profile;
        profile.aaveSelfRepaymentObservations = 99;
        profile.largestObservedBorrowUsdc = 100_000e6;

        PolicyV1.Terms memory terms = policy.quote(profile);
        assertEq(terms.collateralBps, 14_500);
        assertEq(terms.maxBorrowUsdc, 1_000e6);
        assertTrue(terms.reasonFlags & 1 != 0);
    }

    function test_RiskTermsAreBoundedUnderExtremeNegativeEvidence() public view {
        PolicyV1.Profile memory profile;
        profile.largestObservedBorrowUsdc = 40_000e6;
        profile.aaveLiquidationFacts = type(uint32).max;
        profile.sandwichBreaches = type(uint32).max;
        profile.fifoBreaches = type(uint32).max;
        profile.uncompensatedBreaches = type(uint32).max;

        PolicyV1.Terms memory terms = policy.quote(profile);
        assertEq(terms.collateralBps, 20_000);
        assertEq(terms.premiumBps, 2_000);
        assertEq(terms.bondMultiplierBps, 100_000);
        assertEq(terms.minimumBondCtc, 1_000 ether);
        assertEq(terms.maxBorrowUsdc, 125e6);
        assertEq(terms.reasonFlags, 14);
    }
}
