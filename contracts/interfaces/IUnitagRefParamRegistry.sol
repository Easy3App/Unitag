// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagRefParamRegistry {
    /**
     * @dev emit when ref params set
     * @param operator the operator to do the setup
     * @param collectionId the collection to set
     * @return levels the ref percentage of each level
     */
    event RefParamSet(address indexed operator, uint256 collectionId, uint256[] levels);

    /**
     * @dev get the ref params of a collection
     * @param collectionId  the collection to query
     * @param maxLevels maximum levels to query
     * @return levels the ref percentage of each level
     */
    function refParams(uint256 collectionId, uint256 maxLevels) external view returns (uint256[] memory levels);
    
    /**
     * @dev set the ref params of a collection
     * @param collectionId  the collection to set
     * @param levels the ref percentage of each level, maxium 16 levels
     */
    function setRefParams(uint256 collectionId, uint256[] memory levels) external;
}