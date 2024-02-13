// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnitagRelationRegistry {
    /**
     * @dev Set relationship through operators
     * @param collectionId the id of the collection
     * @param accounts  the accounts to set
     * @param signature the signatures of the accounts
     */
    function setParent(uint256 collectionId, address[] calldata accounts, bytes calldata signature) external;

    /**
     * @dev check if the account account has ancestor
     * @param collectionId the id of the collection
     * @param account the account to query
     */
    function hasAncestor(uint256 collectionId, address account) external view returns (bool);

    /**
     * @dev Get direct ancestor of one account(parent)
     * @param collectionId the id of the collection
     * @param account the account to query
     */
    function ancestor(uint256 collectionId, address account) external view returns (address);

    /**
     * @dev Get multi level ancestor of one account
     * @param collectionId the id of the collection
     * @param account the account to query
     * @param level the levels to query
     */
    function ancestors(uint256 collectionId, address account, uint256 level) external view returns (address[] memory _ancestors);
}
