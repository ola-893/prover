// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IPromiseAttestedHeightSource } from "./PromiseBook.sol";
import { PromiseCourtDeployer } from "./PromiseCourtDeployer.sol";
import { NativeQueryVerifierLib } from "./attestcoin/INativeQueryVerifier.sol";

/// @title NativePromiseCourtDeployer
/// @notice Production PromiseCourt deployment pinned to Creditcoin's native precompiles.
contract NativePromiseCourtDeployer is PromiseCourtDeployer {
    address public constant NATIVE_QUERY_VERIFIER = 0x0000000000000000000000000000000000000FD2;
    address public constant NATIVE_CHAIN_INFO = 0x0000000000000000000000000000000000000fD3;

    constructor(address registryGovernor)
        PromiseCourtDeployer(
            NativeQueryVerifierLib.getVerifier(), IPromiseAttestedHeightSource(NATIVE_CHAIN_INFO), registryGovernor
        )
    { }
}
