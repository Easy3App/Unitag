// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUnitag.sol";
import "./utils/SignerValidator.sol";

contract UnitagBatchMinter is Ownable {
    event BatchMint(address indexed account, address indexed minter, uint256 count);

    constructor() {}

    function mintBatch(
        address unitag,
        address[] calldata to,
        uint256[] calldata tagId,
        uint256[] calldata amount,
        bool bindImmediately
    ) external onlyOwner {
        uint256 count = to.length;
        for (uint256 index = 0; index < count; ++index) IUnitagSimple(unitag).mint(to[index], tagId[index], amount[index], bindImmediately);
    }
}

interface IUnitagSimple {
    function mint(
        address to,
        uint256 tagId,
        uint256 amount,
        bool bindImmediately
    ) external;
}
