// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { BureauEvidenceSBT } from "../src/BureauEvidenceSBT.sol";

interface VmEvidenceSbt {
    function envUint(string calldata name) external view returns (uint256 value);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @title DeployCc3EvidenceSbt
/// @notice Standalone deployment specification for the CC3 evidence portability layer.
/// @dev It deploys one adminless contract and performs no write against any existing deployment.
contract DeployCc3EvidenceSbt {
    uint256 private constant CC3_CHAIN_ID = 102_031;
    address private constant BUREAU = 0x8Ef418F6E740950cAd8C4fa22A4F7B7990B00D74;
    address private constant ORDERING_COURT = 0xc01f7E27D4D712241B1cAAD972E0FC589146c5Ff;
    address private constant AAVE_ADAPTER = 0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4;
    bytes32 private constant BUREAU_CODE_HASH = 0x6bb9e01446f7d8c6585b082b33d7918fb1a8283ed4be18a356a8935165afa84c;
    bytes32 private constant ORDERING_COURT_CODE_HASH =
        0x408638df0eae96be9efeabfc29b1c024618c8b20594e8d06428202b82948d316;
    bytes32 private constant AAVE_ADAPTER_CODE_HASH =
        0x23161f6b410872bc04a3ea162cfc01d496073ae521b3a1138be7d7bba20b942f;
    VmEvidenceSbt private constant VM = VmEvidenceSbt(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 expected, uint256 actual);
    error DependencyCodeHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error DeploymentWiringMismatch();
    error ERC5192InterfaceMissing();

    function run() external returns (BureauEvidenceSBT evidenceSbt) {
        if (block.chainid != CC3_CHAIN_ID) revert WrongChain(CC3_CHAIN_ID, block.chainid);
        _requireCodeHash(BUREAU, BUREAU_CODE_HASH);
        _requireCodeHash(ORDERING_COURT, ORDERING_COURT_CODE_HASH);
        _requireCodeHash(AAVE_ADAPTER, AAVE_ADAPTER_CODE_HASH);

        uint256 deployerKey = VM.envUint("CREDITCOIN_PRIVATE_KEY");
        VM.startBroadcast(deployerKey);
        evidenceSbt = new BureauEvidenceSBT(BUREAU, ORDERING_COURT, AAVE_ADAPTER);
        VM.stopBroadcast();

        if (
            address(evidenceSbt.PERFORMANCE_BUREAU()) != BUREAU
                || address(evidenceSbt.ORDERING_COURT()) != ORDERING_COURT
                || address(evidenceSbt.AAVE_ADAPTER()) != AAVE_ADAPTER
        ) {
            revert DeploymentWiringMismatch();
        }
        if (!evidenceSbt.supportsInterface(0xb45a3c0e)) revert ERC5192InterfaceMissing();
    }

    function _requireCodeHash(address dependency, bytes32 expected) private view {
        bytes32 actual = dependency.codehash;
        if (actual != expected) revert DependencyCodeHashMismatch(dependency, expected, actual);
    }
}
