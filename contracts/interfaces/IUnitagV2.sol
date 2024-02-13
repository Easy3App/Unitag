// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC1155SoulBond.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

interface IUnitagV2 is IERC1155SoulBond {
    event CollectionCreated(address indexed operator, string collectionName);
    event CollectionURIChanged(address indexed operator, string collectionName, string newUri);
    event OwnershipTransferred(address indexed operator, address indexed newOwner, string collectionName);
    event SetupTag(address indexed operator, string collectionName, string tagName, uint256 value, uint256 maxSupply, uint256 supply, address externalTag);
    event CollectionValueChanged(address indexed source, uint256 id, uint256 value);
    event OperatorAdded(address indexed operator, address indexed addedOperator, string collectionName);
    event OperatorRemoved(address indexed operator, address indexed removedOperator, string collectionName);

    function createCollection(string calldata collectionName, string calldata uri_, address callbackHandler) external returns (uint256 collectionId);

    function setupTag(string calldata collectionName, string calldata tagName, uint256 value, uint256 maxSupply, uint256 releasedSupply) external returns (uint256 tagId);

    function editTag(string calldata collectionName, string calldata tagName, uint256 value, uint256 releasedSupply) external;

    function transferOwner(string calldata collectionName, address newOwner) external;

    function addOperator(string calldata collectionName, address operator) external;

    function removeOperator(string calldata collectionName, address operator) external;
    
    function bindExternal(address source, uint256 tagId, uint256 amount) external;

    function mint(address to, uint256 tagId, uint256 maxAmount, bool bindImmediately) external returns (uint256 mintAmount);

    function bind(address source, uint256 tagId, uint256 value) external;

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata maxAmounts, bool bindImmediately) external returns (uint256[] memory mintAmounts);

    function bindBatch(address source, uint256[] calldata tagIds, uint256[] calldata amounts) external;

    function available(string calldata collectionName) external view returns (bool);

    function collectionById(uint256 collectionId) external view returns (address owner, string memory name, string memory uri_);

    function collectionByName(string calldata collectionName) external view returns (uint256 collectionId, address owner, string memory name, string memory uri_);

    function isOperatorById(uint256 collectionId, address operator) external view returns (bool);

    function isOperatorByName(string calldata collectionName, address operator) external view returns (bool);

    function operatorsById(uint256 collectionId) external view returns (address[] memory operators_);

    function operatorsByName(string calldata collectionName) external view returns (address[] memory operators_);

    function tagById(uint256 tagId) external view returns (uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName);

    function tagByName(
        string calldata collectionName,
        string calldata tagName
    ) external view returns (uint256 tagId, uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName);

    function tagByFullName(
        string calldata tagFullName
    ) external view returns (uint256 tagId, uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName);
}
