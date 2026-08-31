// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IPromiseAttestedHeightSource, PromiseBook } from "./PromiseBook.sol";
import { PromiseCourt } from "./PromiseCourt.sol";
import { PromiseSourceRegistry } from "./PromiseSourceRegistry.sol";
import { INativeQueryVerifier } from "./attestcoin/INativeQueryVerifier.sol";

/// @title PromiseCourtDeployer
/// @notice Atomically deploys and permanently wires one PromiseBook and PromiseCourt.
/// @dev PromiseBook recognizes this constructor as its deployer, so court initialization can
///      happen exactly once without leaving a post-deployment race or mutable administrator.
contract PromiseCourtDeployer {
    PromiseBook public immutable PROMISE_BOOK;
    PromiseCourt public immutable PROMISE_COURT;
    PromiseSourceRegistry public immutable SOURCE_REGISTRY;

    event PromiseCourtSystemDeployed(
        address indexed promiseBook, address indexed promiseCourt, address indexed sourceRegistry
    );

    constructor(INativeQueryVerifier verifier, IPromiseAttestedHeightSource chainInfo, address registryGovernor) {
        PromiseSourceRegistry registry = new PromiseSourceRegistry(registryGovernor);
        PromiseBook book = new PromiseBook(address(chainInfo), address(registry));
        PromiseCourt court = new PromiseCourt(verifier, book);
        book.initializeCourt(address(court));

        SOURCE_REGISTRY = registry;
        PROMISE_BOOK = book;
        PROMISE_COURT = court;
        emit PromiseCourtSystemDeployed(address(book), address(court), address(registry));
    }
}
