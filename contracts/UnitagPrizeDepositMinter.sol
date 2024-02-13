// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PrizeDepositStorageV2.sol";
import "./interfaces/IUnitag.sol";
import "./interfaces/IUnitagMinter.sol"; 
import "./interfaces/IUnitagRelationRegistry.sol";

contract UnitagPrizeDepositMinter is PrizeDepositStorageV2 {
    IUnitag public immutable unitag;
    IUnitagMinter public immutable unitagMinter;

    constructor(address unitag_, address unitagMinter_, address relationRegistry_) PrizeDepositStorageV2(relationRegistry_) {
        unitag = IUnitag(unitag_);
        unitagMinter = IUnitagMinter(unitagMinter_);
    }

    function prizeOf(string calldata tagFullName) public view returns (PrizePackage[] memory prizes) {
        (uint256 tagId, , , ) = unitag.tagByFullName(tagFullName);
        prizes = _prizeOf(tagId);
    }

    function prizePoolOf(string calldata collectionName, address payToken) public view returns (uint256) {
        (uint256 collectionId, , , ) = unitag.collectionByName(collectionName);
        return _prizePoolOf(collectionId, payToken);
    }

    function setRefParams(string calldata collectionName, uint256 feePercentage, uint256 level1, uint256 level2) external {
        (uint256 collectionId, address owner, , ) = unitag.collectionByName(collectionName);
        require(owner == msg.sender, "Require collection owner");
        _setRefParams(msg.sender, collectionId, feePercentage, level1, level2);
    }

    function refParams(string calldata collectionName) public view returns (uint256 feePercentage, uint256 level1, uint256 level2) {
        (uint256 collectionId, , , ) = unitag.collectionByName(collectionName);
        (feePercentage, level1, level2) = _refParams(collectionId);
    }

    function depositPrize(string calldata collectionName, address payToken, uint256 amount) external payable {
        (uint256 collectionId, , , ) = unitag.collectionByName(collectionName);
        _depositPrize(msg.sender, collectionId, payToken, amount);
    }

    function withdrawPrize(string calldata collectionName, address payToken, uint256 amount, address recipient) external {
        (uint256 collectionId, address owner, , ) = unitag.collectionByName(collectionName);
        require(owner == msg.sender, "Require collection owner");
        _withdrawPrize(recipient, collectionId, payToken, amount);
    }

    function setupPrize(string calldata collectionName, string calldata tagName, address payToken, uint32 supply, uint192 unitShare) external {
        (, address owner, , ) = unitag.collectionByName(collectionName);
        require(owner == msg.sender, "Require collection owner");
        (uint256 tagId, , , ) = unitag.tagByName(collectionName, tagName);
        _setupPrize(msg.sender, tagId, payToken, supply, unitShare);
    }

    function mint(address to, uint256 tagId, uint256 amount, bool bindImmediately, bytes calldata signature) external {
        unitagMinter.mint(to, tagId, amount, bindImmediately, signature);
        if (bindImmediately) {
            (uint256 collectionId, , ) = unitag.tagById(tagId);
            _claimPrize(to, collectionId, tagId, amount);
        }
    }

    function mintBatch(address to, uint256[] calldata tagIds, uint256[] calldata amounts, bool bindImmediately, bytes calldata signature) external {
        unitagMinter.mintBatch(to, tagIds, amounts, bindImmediately, signature);
        if (bindImmediately) {
            uint256 tagLength = tagIds.length;
            if (tagLength > 0) {
                (uint256 collectionId, , ) = unitag.tagById(tagIds[0]);
                for (uint256 index = 0; index < tagLength; ++index) {
                    _claimPrize(to, collectionId, tagIds[index], amounts[index]);
                }
            }
        }
    }

    function validAsCollectionOwner(uint256 collectionId, address target) private view {
        (address owner, , ) = unitag.collectionById(collectionId);
        require(owner == target, "Require collection owner");
    }
}
