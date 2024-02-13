// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagRelationalPrizeDispatcherV3 {
    function dispatch(string calldata collectionName, address recipient, address payToken, uint256 value) external;

    function dispatch(uint256 collectionId, address recipient, address payToken, uint256 value) external;

    function dispatchBatch(uint256 collectionId, address recipient, address[] calldata payTokens, uint256[] calldata values) external;

    function dispatchFrom(string calldata collectionName, address recipient, address payToken, uint256 value) external;

    function dispatchFrom(uint256 collectionId, address recipient, address payToken, uint256 value) external;

    function dispatchFromBatch(uint256 collectionId, address recipient, address[] calldata payTokens, uint256[] calldata values) external;

    function sweep(address tokenAddress, address recipient) external;

    receive() external payable;
}
