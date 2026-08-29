// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IPromiseAttestedHeightSource, PromiseBook } from "./PromiseBook.sol";
import { PromiseCourt } from "./PromiseCourt.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";

/// @title PromiseCourtDeployer
/// @notice Atomically deploys and permanently wires one PromiseBook and PromiseCourt.
/// @dev PromiseBook recognizes this constructor as its deployer, so court initialization can
///      happen exactly once without leaving a post-deployment race or mutable administrator.
contract PromiseCourtDeployer {
    PromiseBook public immutable PROMISE_BOOK;
    PromiseCourt public immutable PROMISE_COURT;

    event PromiseCourtSystemDeployed(address indexed promiseBook, address indexed promiseCourt);

    constructor(INativeQueryVerifier verifier, IPromiseAttestedHeightSource chainInfo) {
        PromiseBook book = new PromiseBook(address(chainInfo));
        PromiseCourt court = new PromiseCourt(verifier, book);
        book.initializeCourt(address(court));

        PROMISE_BOOK = book;
        PROMISE_COURT = court;
        emit PromiseCourtSystemDeployed(address(book), address(court));
    }
}
