// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "./interfaces/IUnitagRefParamRegistry.sol";

contract UnitagRefParamRegistry is IUnitagRefParamRegistry {
    uint256 public constant PERCENTAGE_BASE = 10000;
    uint256 private constant LEVEL_MAX = 256 / 16;

    IUnitagSimple public immutable unitag;

    mapping(uint256 => uint256) internal _collectionRefParam; // collectionId=>params

    constructor(address unitag_) {
        unitag = IUnitagSimple(unitag_);
    }

    /**
     * @param operator the operator to do the setup
     * @param collectionId  the collection to set
     * @param levels the ref percentage of each level
     */
    function _setRefParams(address operator, uint256 collectionId, uint256[] memory levels) internal {
        require(levels.length <= LEVEL_MAX, "UnitagRelationalPrizeDispatcher: invalid levels");
        uint256 total;
        uint256 composed;
        for (uint256 index = 0; index < levels.length; ++index) {
            composed |= levels[index] << (index << 4);
            total += levels[index];
        }
        require(total < PERCENTAGE_BASE, "UnitagRelationalPrizeDispatcher: invalid total percentage");
        _collectionRefParam[collectionId] = composed;
        emit RefParamSet(operator, collectionId, levels);
    }

    /**
     * @dev get the ref params of a collection
     * @param collectionId  the collection to query
     * @param maxLevels maximum levels to query
     * @return levels the ref percentage of each level
     */
    function refParams(uint256 collectionId, uint256 maxLevels) external view returns (uint256[] memory levels) {
        require(maxLevels <= LEVEL_MAX, "UnitagRelationalPrizeDispatcher: invalid maxLevels");
        uint256 rParams = _collectionRefParam[collectionId];
        levels = new uint256[](maxLevels);
        unchecked {
            for (uint256 index = 0; index < maxLevels; ++index) levels[index] = (rParams >> (index << 4)) & type(uint16).max;
        }
    }

    /**
     * @dev set the ref params of a collection
     * @param collectionId  the collection to set
     * @param levels the ref percentage of each level
     */
    function setRefParams(uint256 collectionId, uint256[] memory levels) external {
        (address owner, , ) = unitag.collectionById(collectionId);
        require(owner == msg.sender, "Require collection owner");
        _setRefParams(msg.sender, collectionId, levels);
    }
}

interface IUnitagSimple {
    function collectionById(uint256 collectionId) external view returns (address owner, string memory name, string memory uri_);
}
