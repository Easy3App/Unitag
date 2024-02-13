// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagMinter {
    function mint(address to, uint256 tagId, uint256 amount, bool bindImmediately, bytes calldata signature) external; 
    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately, bytes calldata signature) external;
}
