// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Minter is IERC20 {
    /**
     * @dev Creates `amount` new tokens for `to`
     *
     * See {ERC721-_mint}.
     *
     * Requirements:
     *
     * - the caller must be a minters.
     */
    function mint(address to, uint256 amount) external;
}
