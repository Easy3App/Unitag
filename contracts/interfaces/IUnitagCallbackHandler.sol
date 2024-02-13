// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagCallbackHandler {
    function tokenBinded(
        address to,
        uint256 id,
        uint256 value,
        uint256 amount
    ) external returns (uint256);

    function tokenBindedBatch(
        address to,
        uint256 id,
        uint256[] calldata values,
        uint256[] calldata amounts
    ) external returns (uint256);
}
