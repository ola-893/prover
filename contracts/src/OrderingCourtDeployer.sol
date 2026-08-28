// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CovenantBook, IAttestedHeightSource } from "./CovenantBook.sol";
import { OrderingCourt } from "./OrderingCourt.sol";
import { PerformanceBureau } from "./PerformanceBureau.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";

/// @title OrderingCourtDeployer
/// @notice Constructor-time deterministic deployment for CovenantBook's circular immutable wiring.
/// @dev The deployer creates its two children while it is being constructed: CovenantBook at
///      CREATE nonce 1 and OrderingCourt at nonce 2. This keeps runtime code small enough for
///      EIP-170 while avoiding mutable initialization, privileged setters, and placeholder courts.
///      The injectable form is for tests; production uses NativeOrderingCourtDeployer.
contract OrderingCourtDeployer {
    address public immutable PREDICTED_COURT;
    CovenantBook public immutable COVENANT_BOOK;
    OrderingCourt public immutable ORDERING_COURT;

    event OrderingCourtSystemDeployed(address indexed covenantBook, address indexed orderingCourt);

    error UnexpectedCourtAddress(address expected, address actual);

    constructor(
        INativeQueryVerifier verifier,
        IAttestedHeightSource heightSource,
        PerformanceBureau performanceBureau
    ) {
        address predictedCourt = _nonceTwoCreateAddress(address(this));
        PREDICTED_COURT = predictedCourt;

        CovenantBook book = new CovenantBook(address(heightSource), predictedCourt, predictedCourt);
        OrderingCourt court = new OrderingCourt(verifier, book, performanceBureau);
        if (address(court) != predictedCourt) revert UnexpectedCourtAddress(predictedCourt, address(court));

        COVENANT_BOOK = book;
        ORDERING_COURT = court;
        emit OrderingCourtSystemDeployed(address(book), address(court));
    }

    function _nonceTwoCreateAddress(address factory) private pure returns (address predicted) {
        // RLP([factory, 2]) = 0xd6 || 0x94 || factory || 0x02.
        bytes32 digest = keccak256(abi.encodePacked(hex"d694", factory, hex"02"));
        // The CREATE address is the low 160 bits of the digest.
        // forge-lint: disable-next-line(unsafe-typecast)
        predicted = address(uint160(uint256(digest)));
    }
}
