// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { PolicyV1 } from "./PolicyV1.sol";

interface IPerformanceBureauView {
    function termsOf(address subject) external view returns (PolicyV1.Terms memory);
}

/// @title DemoLender
/// @notice Creates immutable Creditcoin loan offers from PerformanceBureau terms.
/// @dev This is an underwriting demonstration, not a production lending pool. Collateral quotes
///      use an explicit fixture conversion of 1 CTC = 1 USDC so the risk-policy effect is visible
///      without disguising an owner-controlled or unproven price as Attestcoin evidence.
contract DemoLender {
    uint256 public constant USDC_TO_CTC_WEI = 1e12;

    struct Offer {
        address borrower;
        uint128 principalUsdc;
        uint128 requiredCollateralCtc;
        uint64 createdAt;
        uint64 expiresAt;
        PolicyV1.Terms terms;
    }

    IPerformanceBureauView public immutable BUREAU;
    address public owner;
    uint64 public nextOfferNonce;

    mapping(bytes32 offerId => Offer offer) private _offers;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OfferCreated(
        bytes32 indexed offerId,
        address indexed borrower,
        uint128 principalUsdc,
        uint128 requiredCollateralCtc,
        uint16 collateralBps,
        uint16 premiumBps,
        uint64 expiresAt
    );

    error NotOwner(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error ZeroValidityPeriod();
    error ExceedsBorrowLimit(uint128 requested, uint128 maximum);

    constructor(address bureau) {
        if (bureau == address(0)) revert ZeroAddress();
        BUREAU = IPerformanceBureauView(bureau);
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

    function offerOf(bytes32 offerId) external view returns (Offer memory) {
        return _offers[offerId];
    }

    function quote(address borrower, uint128 principalUsdc)
        external
        view
        returns (PolicyV1.Terms memory terms, uint128 requiredCollateralCtc)
    {
        return _quote(borrower, principalUsdc);
    }

    /// @notice Freezes the current bureau terms into a lender-signed offer.
    function makeOffer(address borrower, uint128 principalUsdc, uint64 validFor)
        external
        onlyOwner
        returns (bytes32 offerId)
    {
        if (borrower == address(0)) revert ZeroAddress();
        if (validFor == 0) revert ZeroValidityPeriod();

        (PolicyV1.Terms memory terms, uint128 collateral) = _quote(borrower, principalUsdc);
        uint64 nonce = nextOfferNonce++;
        uint64 createdAt = uint64(block.timestamp);
        uint64 expiresAt = createdAt + validFor;
        offerId = keccak256(abi.encode(block.chainid, address(this), borrower, nonce));

        _offers[offerId] = Offer({
            borrower: borrower,
            principalUsdc: principalUsdc,
            requiredCollateralCtc: collateral,
            createdAt: createdAt,
            expiresAt: expiresAt,
            terms: terms
        });

        emit OfferCreated(
            offerId, borrower, principalUsdc, collateral, terms.collateralBps, terms.premiumBps, expiresAt
        );
    }

    function _quote(address borrower, uint128 principalUsdc)
        private
        view
        returns (PolicyV1.Terms memory terms, uint128 requiredCollateralCtc)
    {
        if (borrower == address(0)) revert ZeroAddress();
        if (principalUsdc == 0) revert ZeroAmount();

        terms = BUREAU.termsOf(borrower);
        if (principalUsdc > terms.maxBorrowUsdc) {
            revert ExceedsBorrowLimit(principalUsdc, terms.maxBorrowUsdc);
        }

        uint256 collateral = uint256(principalUsdc) * USDC_TO_CTC_WEI * terms.collateralBps / 10_000;
        // The principal is capped at 10,000e6 and collateral at 200%, so this is at most 20,000e18.
        // forge-lint: disable-next-line(unsafe-typecast)
        requiredCollateralCtc = uint128(collateral);
    }
}
