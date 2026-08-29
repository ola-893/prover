// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PolicyV1 } from "./PolicyV1.sol";

/// @title PerformanceBureau
/// @notice Append-only, explainable performance records for borrowers and service operators.
/// @dev Proof adapters and courts are reporters. Reporter permissions are scoped by evidence kind,
///      so an Aave adapter cannot manufacture an ordering breach and a court cannot manufacture
///      a repayment. Attestcoin verification will live in those reporter contracts; this contract
///      is the shared record and policy boundary.
contract PerformanceBureau {
    enum EvidenceKind {
        AaveBorrow,
        AaveRepay,
        AaveSelfRepaymentObservation,
        AaveLiquidation,
        SandwichBreach,
        FifoBreach
    }

    struct EvidenceMeta {
        address subject;
        address reporter;
        EvidenceKind kind;
        uint64 recordedAt;
        uint128 value;
        bool uncompensated;
    }

    address public owner;

    mapping(address subject => PolicyV1.Profile profile) private _profiles;
    mapping(address reporter => uint256 permissionMask) public reporterPermissions;
    mapping(bytes32 evidenceId => EvidenceMeta meta) private _evidence;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ReporterPermissionsUpdated(address indexed reporter, uint256 previousMask, uint256 newMask);
    event EvidenceRecorded(
        bytes32 indexed evidenceId,
        address indexed subject,
        address indexed reporter,
        EvidenceKind kind,
        uint128 value,
        bool uncompensated
    );
    event TermsRepriced(
        address indexed subject,
        bytes32 indexed evidenceId,
        uint16 previousCollateralBps,
        uint16 newCollateralBps,
        uint128 previousMaxBorrowUsdc,
        uint128 newMaxBorrowUsdc,
        uint16 previousPremiumBps,
        uint16 newPremiumBps,
        uint128 previousMinimumBondCtc,
        uint128 newMinimumBondCtc
    );

    error NotOwner(address caller);
    error ZeroAddress();
    error ZeroEvidenceId();
    error UnauthorizedReporter(address reporter, EvidenceKind kind);
    error EvidenceAlreadyRecorded(bytes32 evidenceId);
    error InvalidEvidenceValue(EvidenceKind kind, uint128 value);
    error InvalidUncompensatedFlag(EvidenceKind kind);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() private view {
        if (msg.sender != owner) revert NotOwner(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    /// @notice Grants a reporter an explicit bitmask of evidence kinds it may submit.
    function setReporterPermissions(address reporter, uint256 newMask) external onlyOwner {
        if (reporter == address(0)) revert ZeroAddress();
        uint256 previous = reporterPermissions[reporter];
        reporterPermissions[reporter] = newMask;
        emit ReporterPermissionsUpdated(reporter, previous, newMask);
    }

    function permissionFor(EvidenceKind kind) public pure returns (uint256) {
        return uint256(1) << uint8(kind);
    }

    function profileOf(address subject) external view returns (PolicyV1.Profile memory) {
        return _profiles[subject];
    }

    function termsOf(address subject) external view returns (PolicyV1.Terms memory) {
        return PolicyV1.quote(_profiles[subject]);
    }

    function evidenceOf(bytes32 evidenceId) external view returns (EvidenceMeta memory) {
        return _evidence[evidenceId];
    }

    function evidenceRecorded(bytes32 evidenceId) external view returns (bool) {
        return _evidence[evidenceId].reporter != address(0);
    }

    /// @notice Applies one verified fact to a subject's profile exactly once.
    /// @param value An observation's referenced Borrow amount, or CTC actually slashed for a
    ///              breach. Raw borrow/repay/liquidation facts may carry informational values.
    function recordEvidence(address subject, bytes32 evidenceId, EvidenceKind kind, uint128 value, bool uncompensated)
        external
    {
        uint256 requiredPermission = permissionFor(kind);
        if (reporterPermissions[msg.sender] & requiredPermission == 0) {
            revert UnauthorizedReporter(msg.sender, kind);
        }
        if (subject == address(0)) revert ZeroAddress();
        if (evidenceId == bytes32(0)) revert ZeroEvidenceId();
        if (_evidence[evidenceId].reporter != address(0)) revert EvidenceAlreadyRecorded(evidenceId);

        bool isBreach = kind == EvidenceKind.SandwichBreach || kind == EvidenceKind.FifoBreach;
        if (kind == EvidenceKind.AaveSelfRepaymentObservation && value == 0) {
            revert InvalidEvidenceValue(kind, value);
        }
        if (uncompensated && !isBreach) revert InvalidUncompensatedFlag(kind);

        PolicyV1.Profile storage profile = _profiles[subject];
        PolicyV1.Terms memory previousTerms = PolicyV1.quote(profile);

        if (kind == EvidenceKind.AaveBorrow) {
            ++profile.aaveBorrowFacts;
        } else if (kind == EvidenceKind.AaveRepay) {
            ++profile.aaveRepayFacts;
        } else if (kind == EvidenceKind.AaveSelfRepaymentObservation) {
            ++profile.aaveSelfRepaymentObservations;
            if (value > profile.largestObservedBorrowUsdc) profile.largestObservedBorrowUsdc = value;
        } else if (kind == EvidenceKind.AaveLiquidation) {
            ++profile.aaveLiquidationFacts;
        } else if (kind == EvidenceKind.SandwichBreach) {
            ++profile.sandwichBreaches;
            profile.totalSlashedCtc += value;
        } else {
            ++profile.fifoBreaches;
            profile.totalSlashedCtc += value;
        }

        if (uncompensated) ++profile.uncompensatedBreaches;

        _evidence[evidenceId] = EvidenceMeta({
            subject: subject,
            reporter: msg.sender,
            kind: kind,
            recordedAt: uint64(block.timestamp),
            value: value,
            uncompensated: uncompensated
        });

        PolicyV1.Terms memory newTerms = PolicyV1.quote(profile);
        emit EvidenceRecorded(evidenceId, subject, msg.sender, kind, value, uncompensated);
        emit TermsRepriced(
            subject,
            evidenceId,
            previousTerms.collateralBps,
            newTerms.collateralBps,
            previousTerms.maxBorrowUsdc,
            newTerms.maxBorrowUsdc,
            previousTerms.premiumBps,
            newTerms.premiumBps,
            previousTerms.minimumBondCtc,
            newTerms.minimumBondCtc
        );
    }
}
