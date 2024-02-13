// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

interface IERC1155SoulBond is IERC1155, IERC1155MetadataURI {
    event BoundSingle(address indexed operator, address indexed source, uint256 id, uint256 value);
    event BoundBatch(address indexed operator, address indexed source, uint256[] id, uint256[] value);
   
    function boundOf(address account, uint256 id) external view returns (uint256 amount); 
    function boundOfBatch(address[] memory accounts, uint256[] memory ids) external view returns (uint256[] memory amounts); 
}
