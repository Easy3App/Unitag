// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC1155SoulBond.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

interface IUnitag is IERC1155SoulBond {
    event CollectionCreated(address indexed operator, string collectionName);
    event CollectionURIChanged(address indexed operator, string collectionName, string newUri);
    event OwnershipTransferred(address indexed operator, address indexed newOwner, string collectionName);
    event SetupTag(address indexed operator, string collectionName, string tagName, uint256 value); 
    event CollectionValueChanged(address indexed source, uint256 id, uint256 value);
    event OperatorAdded(address indexed operator, address indexed addedOperator, string collectionName);
    event OperatorRemoved(address indexed operator, address indexed removedOperator, string collectionName);

    function createCollection(string calldata collectionName, string calldata uri_, address callbackHandler) external returns (uint256 collectionId);

    function setupTag(string calldata collectionName, string calldata tagName, uint256 value) external;

    function transferOwner(string calldata collectionName, address newOwner) external;

    function addOperator(string calldata collectionName, address operator) external;

    function removeOperator(string calldata collectionName, address operator) external;

    function mint(address to, uint256 tagId, uint256 amount, bool bindImmediately) external;

    function bind(address source, uint256 tagId, uint256 value) external;

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately) external;

    function bindBatch(address source, uint256[] calldata tagIds, uint256[] calldata amounts) external;

    function available(string calldata collectionName) external view returns (bool);

    function collectionById(uint256 collectionId) external view returns (address owner, string memory name, string memory uri_);

    function collectionByName(string calldata collectionName) external view returns (uint256 collectionId, address owner, string memory name, string memory uri_);

    function operatorsById(uint256 collectionId) external view returns (address[] memory operators_);

    function operatorsByName(string calldata collectionName) external view returns (address[] memory operators_);

    function tagById(uint256 tagId) external view returns (uint256 collectionId, uint256 value, string memory name);

    function tagByName(string calldata collectionName, string calldata tagName) external view returns (uint256 tagId, uint256 collectionId, uint256 value, string memory name);

    function tagByFullName(string calldata tagFullName) external view returns (uint256 tagId, uint256 collectionId, uint256 value, string memory name);
}
