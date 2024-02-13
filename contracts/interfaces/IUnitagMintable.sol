// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagMintable {
    function mint(address to, uint256 tagId, uint256 amount, bool bindImmediately) external;

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately) external;
}
