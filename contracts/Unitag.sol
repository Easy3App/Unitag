// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IUnitagCallbackHandler.sol";
import "./interfaces/IUnitag.sol";
import "./library/UnitagLib.sol";

contract Unitag is ERC1155, Multicall, IUnitag {
    using UnitagLib for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    address private constant ZeroAddress = address(0x0);

    struct Collection {
        EnumerableSet.AddressSet operators;
        //       uint256[] tagIds;
        address callbackHandler;
        address owner;
        string name;
        string uri;
    }

    struct Tag {
        uint256 collectionId;
        uint256 value;
        string name;
    }

    mapping(uint256 => Collection) private _collections;
    mapping(uint256 => Tag) private _tags;
    mapping(uint256 => mapping(address => uint256)) private _boundBalances;

    constructor() ERC1155("") {}

    function createCollection(string calldata collectionName, string calldata uri_, address callbackHandler) public returns (uint256 collectionId) {
        require(available(collectionName), "Collection name is not available");
        collectionId = UnitagLib.collectionNameToId(collectionName);
        _collections[collectionId].owner = msg.sender;
        _collections[collectionId].callbackHandler = callbackHandler;
        _collections[collectionId].name = collectionName;
        _collections[collectionId].uri = uri_;
        emit CollectionCreated(msg.sender, collectionName);
    }

    function setCollectionUri(string calldata collectionName, string calldata uri_) public {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        _collections[collectionId].uri = uri_;
        emit CollectionURIChanged(msg.sender, collectionName, uri_);
    }

    function setupTag(string calldata collectionName, string calldata tagName, uint256 value) public {
        require(validTagName(bytes(tagName)), "tag name is not valid");
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        string memory fullTagName = UnitagLib.composeTagFullName(collectionName, tagName);
        uint256 tagId = UnitagLib.tagFullNameToId(fullTagName);
        _tags[tagId].collectionId = collectionId;
        _tags[tagId].value = value;
        _tags[tagId].name = string(fullTagName);
        emit SetupTag(msg.sender, collectionName, string(fullTagName), value);
        //      index = _collections[collectionId].tagIds.length;
        //      _collections[collectionId].tagIds.push(tagId);
    }

    function transferOwner(string calldata collectionName, address newOwner) public {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        _collections[collectionId].owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner, collectionName);
    }

    function addOperator(string calldata collectionName, address operator) public {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        require(_collections[collectionId].operators.add(operator), "Already an operator");
        emit OperatorAdded(msg.sender, operator, collectionName);
    }

    function removeOperator(string calldata collectionName, address operator) public {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        require(_collections[collectionId].operators.remove(operator), "Not an operator");
        emit OperatorRemoved(msg.sender, operator, collectionName);
    }

    function mint(address to, uint256 tagId, uint256 amount, bool bindImmediately) public {
        uint256 collectionId = _tags[tagId].collectionId;
        require(collectionId > 0, "Tag not exists");
        require(_collections[collectionId].operators.contains(msg.sender), "Need collection operator");
        if (bindImmediately) _bind(to, tagId, amount);
        else _mint(to, tagId, amount, "");
    }

    function bind(address source, uint256 tagId, uint256 value) public {
        uint256 collectionId = _tags[tagId].collectionId;
        require(collectionId > 0, "Tag not exists");
        require(source == msg.sender || isApprovedForAll(source, msg.sender), "ERC1155: caller is not token owner nor approved");
        _burn(source, tagId, value);
        _bind(source, tagId, value);
    }

    function _bind(address source, uint256 tagId, uint256 amount) private {
        Tag storage tag = _tags[tagId];
        uint256 collectionId = tag.collectionId;
        _boundBalances[tagId][source] += amount;
        emit BoundSingle(msg.sender, source, tagId, amount);
        if (_collections[collectionId].callbackHandler != ZeroAddress) {
            IUnitagCallbackHandler(_collections[collectionId].callbackHandler).tokenBinded(source, collectionId, tag.value, amount);
        }
    }

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately) public {
        uint256 collectionId = _tags[tagIds[0]].collectionId;
        require(collectionId > 0, "Tag not exists");
        require(_collections[collectionId].operators.contains(msg.sender), "Need collection operator");
        if (bindImmediately) _bindBatch(to, tagIds, amounts);
        else _mintBatch(to, tagIds, amounts, "");
    }

    function bindBatch(address source, uint256[] calldata tagIds, uint256[] calldata amounts) public {
        uint256 collectionId = _tags[tagIds[0]].collectionId;
        require(collectionId > 0, "Tag not exists");
        require(source == msg.sender || isApprovedForAll(source, msg.sender), "ERC1155: caller is not token owner nor approved");
        _burnBatch(source, tagIds, amounts);
        _bindBatch(source, tagIds, amounts);
    }

    function _bindBatch(address source, uint256[] calldata tagIds, uint256[] calldata amounts) private {
        require(tagIds.length == amounts.length, "Unitag: tagIds and amounts length mismatch");
        uint256 collectionId = _tags[tagIds[0]].collectionId;
        uint256[] memory values = new uint256[](tagIds.length);
        for (uint256 index = 0; index < tagIds.length; ++index) {
            require(_tags[tagIds[index]].collectionId == collectionId, "Require same collection");
            _boundBalances[tagIds[index]][source] += amounts[index];
            values[index] = _tags[tagIds[index]].value;
        }
        emit BoundBatch(msg.sender, source, tagIds, amounts);
        if (_collections[collectionId].callbackHandler != ZeroAddress) {
            IUnitagCallbackHandler(_collections[collectionId].callbackHandler).tokenBindedBatch(source, collectionId, values, amounts);
        }
    }

    function boundOf(address account, uint256 id) public view returns (uint256 amount) {
        amount = _boundBalances[id][account];
    }

    function boundOfBatch(address[] memory accounts, uint256[] memory ids) public view returns (uint256[] memory amounts) {
        require(accounts.length == ids.length, "Unitag: accounts and ids length mismatch");
        amounts = new uint256[](accounts.length);
        for (uint256 index = 0; index < accounts.length; ++index) {
            amounts[index] = boundOf(accounts[index], ids[index]);
        }
    }

    function validTagName(bytes calldata name) public pure returns (bool) {
        uint256 bytelength = name.length;
        if (bytelength <= 3) return false;
        // valid for ASCII code in [0x21, 0x7a] except ':'
        for (uint256 index = 0; index < bytelength; ++index) {
            bytes1 oneChar = name[index];
            if (oneChar < 0x21 || oneChar > 0x7a || oneChar == UnitagLib.Separator) return false;
        }
        return true;
    }

    function validCollectionName(bytes calldata name) public pure returns (bool) {
        uint256 bytelength = name.length;
        if (bytelength <= 3) return false;
        // valid for ASCII code in [0x30, 0x39][0x41, 0x5a]
        for (uint256 index = 0; index < bytelength; ++index) {
            bytes1 oneChar = name[index];
            if ((oneChar >= 0x41 && oneChar <= 0x5a) || (oneChar >= 0x30 && oneChar <= 0x39)) continue;
            else return false;
        }
        return true;
    }

    function available(string calldata collectionName) public view override returns (bool) {
        return validCollectionName(bytes(collectionName)) && _collections[UnitagLib.collectionNameToId(collectionName)].owner == ZeroAddress;
    }

    function uri(uint256 id) public view virtual override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        uint256 collectionId = _tags[id].collectionId;
        if (collectionId == 0) collectionId = id;
        return string(abi.encodePacked(_collections[collectionId].uri, id.toString(), ".json"));
    }

    function collectionById(uint256 collectionId) public view returns (address owner, string memory name, string memory uri_) {
        owner = _collections[collectionId].owner;
        name = _collections[collectionId].name;
        uri_ = _collections[collectionId].uri;
    }

    function collectionByName(string calldata collectionName) public view returns (uint256 collectionId, address owner, string memory name, string memory uri_) {
        collectionId = UnitagLib.collectionNameToId(collectionName);
        (owner, name, uri_) = collectionById(collectionId);
    }

    function operatorsById(uint256 collectionId) public view returns (address[] memory operators_) {
        operators_ = _collections[collectionId].operators.toArray();
    }

    function operatorsByName(string calldata collectionName) public view returns (address[] memory operators_) {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        operators_ = operatorsById(collectionId);
    }

    // function tagsOfCollectionById(uint256 collectionId) public view returns (uint256[] memory tagIds) {
    //     tagIds = _collections[collectionId].tagIds;
    // }

    // function tagsOfCollection(string calldata collectionName) public view returns (uint256[] memory tagIds) {
    //     uint256 collectionId = collectionNameToId(collectionName);
    //     tagIds = tagsOfCollectionById(collectionId);
    // }

    function tagById(uint256 tagId) public view returns (uint256 collectionId, uint256 value, string memory name) {
        collectionId = _tags[tagId].collectionId;
        value = _tags[tagId].value;
        name = _tags[tagId].name;
    }

    function tagByName(string calldata collectionName, string calldata tagName) public view returns (uint256 tagId, uint256 collectionId, uint256 value, string memory name) {
        tagId = UnitagLib.tagNameToId(collectionName, tagName);
        (collectionId, value, name) = tagById(tagId);
    }

    function tagByFullName(string calldata tagFullName) public view returns (uint256 tagId, uint256 collectionId, uint256 value, string memory name) {
        tagId = UnitagLib.tagFullNameToId(tagFullName);
        (collectionId, value, name) = tagById(tagId);
    }
}
