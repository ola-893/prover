// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IAttestedHeightSource } from "./CovenantBook.sol";
import { OrderingCourtDeployer } from "./OrderingCourtDeployer.sol";
import { PerformanceBureau } from "./PerformanceBureau.sol";
import { NativeQueryVerifierLib } from "./attestcoin/INativeQueryVerifier.sol";

/// @title NativeOrderingCourtDeployer
/// @notice Production deployment pinned to Creditcoin's Attestcoin and ChainInfo precompiles.
contract NativeOrderingCourtDeployer is OrderingCourtDeployer {
    address public constant NATIVE_QUERY_VERIFIER = 0x0000000000000000000000000000000000000FD2;
    address public constant NATIVE_CHAIN_INFO = 0x0000000000000000000000000000000000000fD3;

    constructor(PerformanceBureau performanceBureau)
        OrderingCourtDeployer(
            NativeQueryVerifierLib.getVerifier(), IAttestedHeightSource(NATIVE_CHAIN_INFO), performanceBureau
        )
    { }
}
