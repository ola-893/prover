// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { NativeAaveEvidenceAdapter } from "../src/AaveEvidenceAdapter.sol";
import { CovenantBook } from "../src/CovenantBook.sol";
import { DemoLender } from "../src/DemoLender.sol";
import { NativeOrderingCourtDeployer } from "../src/NativeOrderingCourtDeployer.sol";
import { OrderingCourt } from "../src/OrderingCourt.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";

interface Vm {
    function envUint(string calldata name) external view returns (uint256 value);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @title DeployCc3Mvp
/// @notice Declarative deployment and wiring specification for Creditcoin CC3 testnet.
/// @dev The signer is read only from the process environment. The source-chain DemoExitVault is
///      deliberately excluded: it belongs on an Attestcoin-supported Ethereum source network.
///      Foundry 1.5 cannot currently fork the raw CC3 RPC because its block response omits
///      mixHash/prevRandao; DEPLOY_CC3.md documents the equivalent direct deployment path.
contract DeployCc3Mvp {
    uint256 private constant CC3_CHAIN_ID = 102_031;
    address private constant CANONICAL_EVM_V1_DECODER = 0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f;
    bytes32 private constant CANONICAL_EVM_V1_DECODER_CODE_HASH =
        0xb549c9d8eaf7d361192f8e363fe98717464441e2dd26e2b3bd1e0725df73a065;
    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant VM = Vm(VM_ADDRESS);

    error WrongChain(uint256 expected, uint256 actual);
    error WrongDecoderCodeHash(bytes32 expected, bytes32 actual);
    error ReporterWiringFailed(address reporter, uint256 expected, uint256 actual);

    function run()
        external
        returns (
            PerformanceBureau bureau,
            NativeOrderingCourtDeployer orderingSystem,
            CovenantBook covenantBook,
            OrderingCourt orderingCourt,
            NativeAaveEvidenceAdapter aaveAdapter,
            DemoLender lender
        )
    {
        if (block.chainid != CC3_CHAIN_ID) {
            revert WrongChain(CC3_CHAIN_ID, block.chainid);
        }
        bytes32 decoderCodeHash = CANONICAL_EVM_V1_DECODER.codehash;
        if (decoderCodeHash != CANONICAL_EVM_V1_DECODER_CODE_HASH) {
            revert WrongDecoderCodeHash(CANONICAL_EVM_V1_DECODER_CODE_HASH, decoderCodeHash);
        }

        uint256 deployerKey = VM.envUint("CREDITCOIN_PRIVATE_KEY");
        VM.startBroadcast(deployerKey);

        bureau = new PerformanceBureau();
        orderingSystem = new NativeOrderingCourtDeployer(bureau);
        covenantBook = orderingSystem.COVENANT_BOOK();
        orderingCourt = orderingSystem.ORDERING_COURT();
        aaveAdapter = new NativeAaveEvidenceAdapter(bureau);
        lender = new DemoLender(address(bureau));

        uint256 courtMask = _permission(PerformanceBureau.EvidenceKind.SandwichBreach)
            | _permission(PerformanceBureau.EvidenceKind.FifoBreach);
        uint256 aaveMask = _permission(PerformanceBureau.EvidenceKind.AaveBorrow)
            | _permission(PerformanceBureau.EvidenceKind.AaveRepay)
            | _permission(PerformanceBureau.EvidenceKind.AaveSelfRepaymentObservation);

        bureau.setReporterPermissions(address(orderingCourt), courtMask);
        bureau.setReporterPermissions(address(aaveAdapter), aaveMask);

        VM.stopBroadcast();

        _requirePermission(bureau, address(orderingCourt), courtMask);
        _requirePermission(bureau, address(aaveAdapter), aaveMask);
    }

    function _permission(PerformanceBureau.EvidenceKind kind) private pure returns (uint256) {
        return uint256(1) << uint8(kind);
    }

    function _requirePermission(PerformanceBureau bureau, address reporter, uint256 expected) private view {
        uint256 actual = bureau.reporterPermissions(reporter);
        if (actual != expected) revert ReporterWiringFailed(reporter, expected, actual);
    }
}
