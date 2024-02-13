// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../library/TransferHelper.sol";
import "./Multicall.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DropshipV11 is Multicall {
    event Sweep(address indexed operator, address indexed recipient, address token, uint256 amount);

    function nativeCurrencyBatchTransfer(address[] calldata accounts, uint256[] calldata amounts) external payable {
        uint256 length = accounts.length;
        require(length == amounts.length, "accounts != amounts");
        for (uint256 index = 0; index < length; ) {
            TransferHelper.safeTransferETH(accounts[index], amounts[index]);
            unchecked {
                ++index;
            }
        }
        uint256 balance = address(this).balance;
        if (balance > 0) TransferHelper.safeTransferETH(msg.sender, balance);
    }

    function erc20BatchTransfer(address tokenAddress, address[] calldata accounts, uint256[] calldata amounts, uint256 totalAmount) public {
        uint256 length = accounts.length;
        require(length == amounts.length, "accounts != amounts");
        TransferHelper.safeTransferFrom(tokenAddress, msg.sender, address(this), totalAmount);
        for (uint256 index = 0; index < length; ) {
            TransferHelper.safeTransfer(tokenAddress, accounts[index], amounts[index]);
            unchecked {
                ++index;
            }
        }
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance > 0) TransferHelper.safeTransfer(tokenAddress, msg.sender, balance);
    }

    function erc721BatchTransfer(address tokenAddress, address[] calldata accounts, uint256[] calldata ids) public {
        require(accounts.length == ids.length, "accounts != ids");
        IERC721 token = IERC721(tokenAddress);
        for (uint256 index = 0; index < accounts.length; ) {
            token.safeTransferFrom(msg.sender, accounts[index], ids[index]);
            unchecked {
                ++index;
            }
        }
    }

    function erc1155BatchTransfer(address tokenAddress, address[] calldata accounts, uint256[] calldata ids, uint256[] calldata amounts) public {
        require(accounts.length == ids.length, "accounts != ids");
        require(accounts.length == ids.length, "accounts != amounts");
        IERC1155 token = IERC1155(tokenAddress);
        for (uint256 index = 0; index < accounts.length; ) {
            token.safeTransferFrom(msg.sender, accounts[index], ids[index], amounts[index], "");
            unchecked {
                ++index;
            }
        }
    }

    function sweep(address tokenAddress, address recipient) external {
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance > 0) {
            TransferHelper.safeTransfer(tokenAddress, recipient, balance);
            emit Sweep(msg.sender, recipient, tokenAddress, balance);
        }
    }
}
