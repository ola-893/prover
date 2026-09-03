// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ERC-5192 Minimal Soulbound NFT interface
/// @notice Canonical ERC-165 surface for permanently locked ERC-721 tokens.
interface IERC5192 is IERC165 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    function locked(uint256 tokenId) external view returns (bool);
}
