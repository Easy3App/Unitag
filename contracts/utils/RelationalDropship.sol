// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Dropship.sol";
import "../interfaces/IUnitagRelationRegistry.sol";

contract RelationalDropship is Dropship {
    using SafeERC20 for IERC20;
    ISimplePriceDispatcher public immutable relationalDispatcher;

    constructor(address relationRegistry_) {
        relationalDispatcher = ISimplePriceDispatcher(relationRegistry_);
    }

    function mainnetCurrencyBatchTransfer(string calldata collectionName, address[] calldata accounts, uint256[] calldata amounts) public payable {
        uint256 collectionId = getCollectionIdFromName(collectionName);
        mainnetCurrencyBatchTransfer(collectionId, accounts, amounts);
    }

    function mainnetCurrencyBatchTransfer(uint256 collectionId, address[] calldata accounts, uint256[] calldata amounts) public payable {
        uint256 length = accounts.length;
        require(length == amounts.length, "accounts != amounts");
        sendValue(address(relationalDispatcher), msg.value);
        for (uint256 index = 0; index < length; ++index) {
            relationalDispatcher.transferOutTokenWithAncesors(collectionId, accounts[index], address(0), amounts[index]);
        }
        relationalDispatcher.sweep(address(0), msg.sender);
    }

    function erc20BatchRelationalTransfer(string calldata collectionName, address tokenAddress, address[] calldata accounts, uint256[] calldata amounts, uint256 totalAmount) public {
        uint256 collectionId = getCollectionIdFromName(collectionName);
        erc20BatchRelationalTransfer(collectionId, tokenAddress, accounts, amounts, totalAmount);
    }

    function erc20BatchRelationalTransfer(uint256 collectionId, address tokenAddress, address[] calldata accounts, uint256[] calldata amounts, uint256 totalAmount) public {
        uint256 length = accounts.length;
        require(length == amounts.length, "accounts != amounts");
        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(relationalDispatcher), totalAmount);
        for (uint256 index = 0; index < length; ++index) {
            relationalDispatcher.transferOutTokenWithAncesors(collectionId, accounts[index], tokenAddress, amounts[index]);
        }
        relationalDispatcher.sweep(tokenAddress, msg.sender);
    }

    function multiCallToDispatcher(bytes[] calldata data) public returns (bytes[] memory results) {
        return relationalDispatcher.multicall(data);
    }

    function getCollectionIdFromName(string calldata collectionName) public view returns (uint256 collectionId) {
        (collectionId, , , ) = IUnitagSimple(relationalDispatcher.unitag()).collectionByName(collectionName);
    }
}

interface ISimplePriceDispatcher {
    function setParent(uint256 collectionId, address[] calldata accounts, bytes calldata signature) external;

    function transferOutTokenWithAncesors(uint256 collectionId, address recipient, address payToken, uint256 value) external;

    function unitag() external view returns (address unitag);

    function relationRegistry() external view returns (address);

    function sweep(address tokenAddress, address recipient) external;

    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}

interface IUnitagSimple {
    function collectionByName(string calldata collectionName) external view returns (uint256 collectionId, address owner, string memory name, string memory uri_);
}
