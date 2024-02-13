// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IUnitagCallbackHandler.sol";
import "./interfaces/IUnitagV2.sol";
import "./interfaces/IUnitagExternalTag.sol";
import "./library/UnitagLib.sol";

contract UnitagV2 is ERC1155, Multicall, IUnitagV2 {
    using UnitagLib for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    address private constant ZeroAddress = address(0x0);
    
    string public constant name = "UnitagV2";
    string public constant symbol = "UNTV2";

    struct Collection {
        EnumerableSet.AddressSet operators;
        address callbackHandler;
        address owner;
        string name;
        string uri;
    }

    struct Tag {
        uint256 collectionId;
        uint256 value;
        uint256 maxSupply;
        uint256 releasedSupply;
        address externalTag;
        string name;
    }

    mapping(uint256 => uint256) private _totalSupply;

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

    function setupTag(string calldata collectionName, string calldata tagName, uint256 value, uint256 maxSupply, uint256 releasedSupply) public returns (uint256 tagId) {
        require(validTagName(bytes(tagName)), "tag name is not valid");
        require(maxSupply >= releasedSupply, "supply exceed maxSupply");
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        address externalTag = ZeroAddress;
        if (_collections[collectionId].owner != msg.sender) {
            //require(IERC165(msg.sender).supportsInterface(type(IUnitagExternalTag).interfaceId), "cannot set to non-unitag721s");
            require(tx.origin == _collections[collectionId].owner, "require collection owner");
            externalTag = msg.sender;
        }

        string memory fullTagName = UnitagLib.composeTagFullName(collectionName, tagName);
        tagId = UnitagLib.tagFullNameToId(fullTagName);
        require(_tags[tagId].collectionId == 0, "tag exists");
        _tags[tagId].collectionId = collectionId;
        if (maxSupply > 0) {
            _tags[tagId].maxSupply = maxSupply;
            _tags[tagId].releasedSupply = releasedSupply;
        }
        _tags[tagId].name = string(fullTagName);
        _tags[tagId].value = value;
        if (externalTag != ZeroAddress) _tags[tagId].externalTag = externalTag;
        emit SetupTag(msg.sender, collectionName, string(fullTagName), value, maxSupply, releasedSupply, externalTag);
    }

    function editTag(string calldata collectionName, string calldata tagName, uint256 value, uint256 releasedSupply) public {
        string memory fullTagName = UnitagLib.composeTagFullName(collectionName, tagName);
        uint256 tagId = UnitagLib.tagFullNameToId(fullTagName);
        uint256 collectionId = _tags[tagId].collectionId;
        require(collectionId != 0, "tag not exists");
        require(_collections[collectionId].owner == msg.sender, "Need collection owner");
        require(totalSupply(tagId) >= releasedSupply, "released supply is exceed totalSupply");
        _tags[tagId].value = value;
        _tags[tagId].releasedSupply = releasedSupply;
        emit SetupTag(msg.sender, collectionName, string(fullTagName), value, _tags[tagId].maxSupply, releasedSupply, _tags[tagId].externalTag);
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

    function bindExternal(address source, uint256 tagId, uint256 amount) external {
        Tag storage tag = _tags[tagId];
        uint256 collectionId = tag.collectionId;
        require(collectionId > 0, "Tag not exists");
        require(tag.externalTag == msg.sender, "cannot only call from external tag");
        _totalSupply[tagId] += amount;
        emit BoundSingle(msg.sender, source, tagId, amount);
        if (_collections[collectionId].callbackHandler != ZeroAddress) {
            IUnitagCallbackHandler(_collections[collectionId].callbackHandler).tokenBinded(source, collectionId, tag.value, amount);
        }
    }

    function mint(address to, uint256 tagId, uint256 maxAmount, bool bindImmediately) public returns (uint256 mintAmount) {
        Tag storage tag = _tags[tagId];
        uint256 collectionId = tag.collectionId;
        require(collectionId > 0, "Tag not exists");
        require(_collections[collectionId].operators.contains(msg.sender), "Need collection operator");
        uint256 supply = totalSupply(tagId);
        uint256 releasedSupply = tag.releasedSupply;
        mintAmount = maxAmount;
        if (releasedSupply > 0) {
            if (supply + maxAmount > releasedSupply) mintAmount = releasedSupply - supply;
        }
        if (mintAmount > 0) {
            address externalTag = tag.externalTag;
            if (externalTag != ZeroAddress) IUnitagExternalTag(externalTag).mint(to, mintAmount, bindImmediately);
            else {
                _totalSupply[tagId] = supply + mintAmount;
                if (bindImmediately) _bind(to, tagId, mintAmount);
                else _mint(to, tagId, mintAmount, "");
            }
        }
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

    // function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately) public {
    //     require(tagIds.length < 256, "Mint tags too much");
    //     uint256 collectionId = _tags[tagIds[0]].collectionId;
    //     require(collectionId > 0, "Tag not exists");
    //     require(_collections[collectionId].operators.contains(msg.sender), "Need collection operator");

    //     uint256[] memory internalIds = new uint[](tagIds.length);
    //     uint256[] memory internalAmounts = new uint[](tagIds.length);
    //     uint256 internalIdx;
    //     for (uint256 index = 0; index < tagIds.length; ++index) {
    //         uint256 tagId = tagIds[index];
    //         address externalTag = _tags[tagId].externalTag;
    //         if (externalTag != ZeroAddress) IUnitagExternalTag(externalTag).mint(to, amounts[index], bindImmediately);
    //         else {
    //             internalIds[internalIdx] = tagId;
    //             internalAmounts[internalIdx] = amounts[index];
    //             ++internalIdx;
    //         }
    //     }
    //     if (internalIdx > 0) {
    //         assembly {
    //             mstore(internalIds, internalIdx)
    //             mstore(internalAmounts, internalIdx)
    //         }
    //         if (bindImmediately) _bindBatch(to, internalIds, internalAmounts);
    //         else _mintBatch(to, internalIds, internalAmounts, "");
    //     }
    // }

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata maxAmounts, bool bindImmediately) public returns (uint256[] memory mintAmount) {
        uint256 collectionId = _tags[tagIds[0]].collectionId;

        require(collectionId > 0, "Tag not exists");
        require(_collections[collectionId].operators.contains(msg.sender), "Need collection operator");

        uint256 iIndex;
        uint256[] memory iIds = new uint256[](tagIds.length);
        uint256[] memory iAmounts = new uint256[](tagIds.length);
        mintAmount = new uint256[](tagIds.length);

        for (uint256 index = 0; index < tagIds.length; ++index) {
            Tag storage tag = _tags[tagIds[index]];
            {
                uint256 supply = totalSupply(tagIds[index]);
                uint256 releasedSupply = tag.releasedSupply;
                if (releasedSupply > 0 && supply + maxAmounts[index] > releasedSupply) mintAmount[index] = releasedSupply - supply;
                else mintAmount[index] = maxAmounts[index];
            }
            if (mintAmount[index] > 0) {
                address externalTag = tag.externalTag;
                if (externalTag != ZeroAddress) {
                    require(tag.collectionId == collectionId, "Require same collection");
                    IUnitagExternalTag(externalTag).mint(to, mintAmount[index], bindImmediately);
                } else {
                    _totalSupply[tagIds[index]] += mintAmount[index];
                    iIds[iIndex] = tagIds[index];
                    iAmounts[iIndex] = mintAmount[index];
                    ++iIndex;
                }
            }
        }
        if (iIndex > 0) {
            if (iIndex != tagIds.length) {
                assembly {
                    mstore(iIds, iIndex)
                    mstore(iAmounts, iIndex)
                }
            }
            if (bindImmediately) _bindBatch(to, iIds, iAmounts);
            else _mintBatch(to, iIds, iAmounts, "");
        }
    }

    function bindBatch(address source, uint256[] calldata tagIds, uint256[] calldata amounts) public {
        uint256 collectionId = _tags[tagIds[0]].collectionId;
        require(collectionId > 0, "Tag not exists");
        require(source == msg.sender || isApprovedForAll(source, msg.sender), "ERC1155: caller is not token owner nor approved");
        _burnBatch(source, tagIds, amounts);
        _bindBatch(source, tagIds, amounts);
    }

    function _bindBatch(address source, uint256[] memory tagIds, uint256[] memory amounts) private {
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
        address externalTag = _tags[id].externalTag;
        if (externalTag != ZeroAddress) amount = IUnitagExternalTag(externalTag).boundOf(account);
        else amount = _boundBalances[id][account];
    }

    function boundOfBatch(address[] memory accounts, uint256[] memory ids) public view returns (uint256[] memory amounts) {
        require(accounts.length == ids.length, "Unitag: accounts and ids length mismatch");
        amounts = new uint256[](accounts.length);
        for (uint256 index = 0; index < accounts.length; ++index) {
            amounts[index] = boundOf(accounts[index], ids[index]);
        }
    }

    function validTagName(bytes calldata collectionName) public pure returns (bool) {
        uint256 bytelength = collectionName.length;
        if (bytelength <= 3) return false;
        // valid for ASCII code in [0x21, 0x7a] except ':'
        for (uint256 index = 0; index < bytelength; ++index) {
            bytes1 oneChar = collectionName[index];
            if (oneChar < 0x21 || oneChar > 0x7a || oneChar == UnitagLib.Separator) return false;
        }
        return true;
    }

    function validCollectionName(bytes calldata collectionName) public pure returns (bool) {
        uint256 bytelength = collectionName.length;
        if (bytelength <= 3) return false;
        // valid for ASCII code in [0x41, 0x5a]
        for (uint256 index = 0; index < bytelength; ++index) {
            bytes1 oneChar = collectionName[index];
            if (oneChar < 0x41 || oneChar > 0x5a) return false;
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

    function collectionById(uint256 collectionId) public view returns (address owner, string memory colName, string memory uri_) {
        owner = _collections[collectionId].owner;
        colName = _collections[collectionId].name;
        uri_ = _collections[collectionId].uri;
    }

    function collectionByName(string calldata collectionName) public view returns (uint256 collectionId, address owner, string memory colName, string memory uri_) {
        collectionId = UnitagLib.collectionNameToId(collectionName);
        (owner, colName, uri_) = collectionById(collectionId);
    }

    function isOperatorById(uint256 collectionId, address operator) public view returns (bool) {
        return _collections[collectionId].operators.contains(operator);
    }

    function isOperatorByName(string calldata collectionName, address operator) public view returns (bool) {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        return _collections[collectionId].operators.contains(operator);
    }

    function operatorsById(uint256 collectionId) public view returns (address[] memory operators_) {
        operators_ = _collections[collectionId].operators.toArray();
    }

    function operatorsByName(string calldata collectionName) public view returns (address[] memory operators_) {
        uint256 collectionId = UnitagLib.collectionNameToId(collectionName);
        operators_ = operatorsById(collectionId);
    }

    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }
  
    function exists(uint256 id) public view virtual returns (bool) {
        return totalSupply(id) > 0;
    }

    // function tagsOfCollectionById(uint256 collectionId) public view returns (uint256[] memory tagIds) {
    //     tagIds = _collections[collectionId].tagIds;
    // }

    // function tagsOfCollection(string calldata collectionName) public view returns (uint256[] memory tagIds) {
    //     uint256 collectionId = collectionNameToId(collectionName);
    //     tagIds = tagsOfCollectionById(collectionId);
    // }

    function tagById(uint256 tagId) public view returns (uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName) {
        collectionId = _tags[tagId].collectionId;
        value = _tags[tagId].value;
        tName = _tags[tagId].name;
        maxSupply = _tags[tagId].maxSupply;
        releasedSupply = _tags[tagId].releasedSupply;
        externalTag = _tags[tagId].externalTag;
    }

    function tagByName(
        string calldata collectionName,
        string calldata tagName
    ) public view returns (uint256 tagId, uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName) {
        tagId = UnitagLib.tagNameToId(collectionName, tagName);
        (collectionId, value, maxSupply, releasedSupply, externalTag, tName) = tagById(tagId);
    }

    function tagByFullName(
        string calldata tagFullName
    ) public view returns (uint256 tagId, uint256 collectionId, uint256 value, uint256 maxSupply, uint256 releasedSupply, address externalTag, string memory tName) {
        tagId = UnitagLib.tagFullNameToId(tagFullName);
        (collectionId, value, maxSupply, releasedSupply, externalTag, tName) = tagById(tagId);
    }
}
