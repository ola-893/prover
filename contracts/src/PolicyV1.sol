// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title PolicyV1
/// @notice A deliberately small, deterministic underwriting policy for the MVP.
/// @dev The policy consumes an evidence vector rather than an opaque score. Values are demo
///      policy parameters, not an assertion that they are actuarially calibrated.
library PolicyV1 {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant CTC = 1e18;

    uint256 internal constant BASE_COLLATERAL_BPS = 15_000;
    uint256 internal constant MIN_COLLATERAL_BPS = 10_000;
    uint256 internal constant MAX_COLLATERAL_BPS = 20_000;
    uint256 internal constant SELF_REPAYMENT_OBSERVATION_DISCOUNT_BPS = 500;
    uint256 internal constant LIQUIDATION_SURCHARGE_BPS = 1_500;
    uint256 internal constant BREACH_SURCHARGE_BPS = 500;

    uint256 internal constant BASE_PREMIUM_BPS = 50;
    uint256 internal constant BREACH_PREMIUM_BPS = 100;
    uint256 internal constant UNCOMPENSATED_PREMIUM_BPS = 100;
    uint256 internal constant MAX_PREMIUM_BPS = 2_000;

    uint256 internal constant BASE_BOND_CTC = 100 * CTC;
    uint256 internal constant BASE_BOND_MULTIPLIER_BPS = 10_000;
    uint256 internal constant BREACH_BOND_MULTIPLIER_BPS = 5_000;
    uint256 internal constant UNCOMPENSATED_BOND_MULTIPLIER_BPS = 5_000;
    uint256 internal constant MAX_BOND_MULTIPLIER_BPS = 100_000;

    uint256 internal constant BASE_BORROW_USDC = 100 * USDC;
    uint256 internal constant MAX_BORROW_USDC = 1_000 * USDC;
    uint256 internal constant OBSERVED_BORROW_UPLIFT_BPS = 100;
    uint256 internal constant LIQUIDATION_LIMIT_PENALTY_BPS = 2_500;
    uint256 internal constant BREACH_LIMIT_PENALTY_BPS = 1_000;
    uint256 internal constant MAX_LIMIT_PENALTY_BPS = 7_500;

    uint256 internal constant REASON_AAVE_SELF_REPAYMENT_OBSERVATION = 1 << 0;
    uint256 internal constant REASON_LIQUIDATION = 1 << 1;
    uint256 internal constant REASON_ORDERING_BREACH = 1 << 2;
    uint256 internal constant REASON_UNCOMPENSATED = 1 << 3;

    /// @notice Verified facts attached to one EVM address.
    /// @dev `largestObservedBorrowUsdc` is the Borrow amount in the largest separately verified
    ///      Aave Borrow + later same-address Repay observation. It is not a claim about a linked
    ///      loan, current debt, timeliness, liquidation absence, or complete credit history.
    struct Profile {
        uint32 aaveBorrowFacts;
        uint32 aaveRepayFacts;
        uint32 aaveSelfRepaymentObservations;
        uint32 aaveLiquidationFacts;
        uint32 sandwichBreaches;
        uint32 fifoBreaches;
        uint32 uncompensatedBreaches;
        uint128 largestObservedBorrowUsdc;
        uint128 totalSlashedCtc;
    }

    /// @notice The terms consumers can quote directly from the evidence vector.
    /// @param collateralBps Required collateral as basis points of principal.
    /// @param premiumBps Service/risk premium in basis points.
    /// @param bondMultiplierBps Multiplier applied to the 100 CTC base operator bond.
    /// @param maxBorrowUsdc Maximum demo loan, denominated in six-decimal USDC units.
    /// @param minimumBondCtc Required operator bond, denominated in CTC wei.
    /// @param reasonFlags Bitset explaining which classes of evidence changed the baseline.
    struct Terms {
        uint16 collateralBps;
        uint16 premiumBps;
        uint32 bondMultiplierBps;
        uint128 maxBorrowUsdc;
        uint128 minimumBondCtc;
        uint256 reasonFlags;
    }

    /// @notice Computes all product terms from an address's verified facts.
    /// @dev Policy V1 is an experimental hackathon policy, not actuarially calibrated. Any number
    ///      of self-repayment observations receives at most one five-percentage-point collateral
    ///      discount, while the capacity uplift is one percent of the largest referenced Borrow
    ///      and the entire limit is capped at 1,000 USDC. Recorded liquidation facts are positive
    ///      inclusions only; a zero count does not establish liquidation absence.
    function quote(Profile memory profile) internal pure returns (Terms memory terms) {
        bool hasSelfRepaymentObservation = profile.aaveSelfRepaymentObservations != 0;
        uint256 breaches = uint256(profile.sandwichBreaches) + uint256(profile.fifoBreaches);

        uint256 observationDiscount = hasSelfRepaymentObservation ? SELF_REPAYMENT_OBSERVATION_DISCOUNT_BPS : 0;
        uint256 collateral = BASE_COLLATERAL_BPS - observationDiscount + uint256(profile.aaveLiquidationFacts)
            * LIQUIDATION_SURCHARGE_BPS + breaches * BREACH_SURCHARGE_BPS;
        collateral = _clamp(collateral, MIN_COLLATERAL_BPS, MAX_COLLATERAL_BPS);

        uint256 capacity =
            BASE_BORROW_USDC + uint256(profile.largestObservedBorrowUsdc) * OBSERVED_BORROW_UPLIFT_BPS / 10_000;
        capacity = _min(capacity, MAX_BORROW_USDC);

        uint256 limitPenalty =
            uint256(profile.aaveLiquidationFacts) * LIQUIDATION_LIMIT_PENALTY_BPS + breaches * BREACH_LIMIT_PENALTY_BPS;
        limitPenalty = _min(limitPenalty, MAX_LIMIT_PENALTY_BPS);
        uint256 maxBorrow = capacity * (10_000 - limitPenalty) / 10_000;

        uint256 premium = BASE_PREMIUM_BPS + breaches * BREACH_PREMIUM_BPS + uint256(profile.uncompensatedBreaches)
            * UNCOMPENSATED_PREMIUM_BPS;
        premium = _min(premium, MAX_PREMIUM_BPS);

        uint256 bondMultiplier = BASE_BOND_MULTIPLIER_BPS + breaches * BREACH_BOND_MULTIPLIER_BPS
            + uint256(profile.uncompensatedBreaches) * UNCOMPENSATED_BOND_MULTIPLIER_BPS;
        bondMultiplier = _min(bondMultiplier, MAX_BOND_MULTIPLIER_BPS);

        uint256 reasons;
        if (hasSelfRepaymentObservation) reasons |= REASON_AAVE_SELF_REPAYMENT_OBSERVATION;
        if (profile.aaveLiquidationFacts != 0) reasons |= REASON_LIQUIDATION;
        if (breaches != 0) reasons |= REASON_ORDERING_BREACH;
        if (profile.uncompensatedBreaches != 0) reasons |= REASON_UNCOMPENSATED;

        // All five casts below are bounded immediately above: 20,000 collateral bps, 2,000 premium
        // bps, 100,000 bond multiplier bps, 1,000e6 USDC and 1,000e18 CTC respectively.
        terms = Terms({
            // forge-lint: disable-next-line(unsafe-typecast)
            collateralBps: uint16(collateral),
            // forge-lint: disable-next-line(unsafe-typecast)
            premiumBps: uint16(premium),
            // forge-lint: disable-next-line(unsafe-typecast)
            bondMultiplierBps: uint32(bondMultiplier),
            // forge-lint: disable-next-line(unsafe-typecast)
            maxBorrowUsdc: uint128(maxBorrow),
            // forge-lint: disable-next-line(unsafe-typecast)
            minimumBondCtc: uint128(BASE_BOND_CTC * bondMultiplier / BASE_BOND_MULTIPLIER_BPS),
            reasonFlags: reasons
        });
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _clamp(uint256 value, uint256 minimum, uint256 maximum) private pure returns (uint256) {
        if (value < minimum) return minimum;
        if (value > maximum) return maximum;
        return value;
    }
}
