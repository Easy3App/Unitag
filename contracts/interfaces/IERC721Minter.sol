// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Minter is IERC721 {
    /**
     * @dev Creates `amount` new tokens for `to`
     *
     * See {ERC721-_mint}.
     *
     * Requirements:
     *
     * - the caller must be a minters.
     */
    function mint(address to, uint256 amount) external returns (uint256);

    /**
     * @dev Destroys `amount` tokens of token type `id` from `account`
     *
     * Requirements:
     *
     * - caller should be self of approved account
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens of token type `id`.
     */
    function burn(uint256 id) external;

    /**
     * @dev Batch version of burn function
     */
    function burnBatch(uint256[] memory ids) external;
}
