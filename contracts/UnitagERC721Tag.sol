// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UnitagERC721TagBase.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard
 */
contract UnitagERC721Tag is UnitagERC721TagBase {
    constructor(
        string memory name_,
        string memory symbol_,
        string memory collectionName_,
        string memory tagName_,
        uint256 value,
        uint256 maxSupply,
        uint256 releasedSupply,
        address unitagV2_
    ) UnitagERC721TagBase(name_, symbol_, collectionName_, tagName_, value, maxSupply, releasedSupply, unitagV2_) {}
}
