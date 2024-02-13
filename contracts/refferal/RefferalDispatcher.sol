// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IUnitagRelationRegistry.sol";

abstract contract RefferalDispatcher is Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    event DepositPrize(address indexed sender, uint256 indexed collectionId, address indexed payToken, uint256 amount);
    event WithdrawPrize(address indexed sender, uint256 indexed collectionId, address indexed payToken, uint256 amount);
    event SetupPrize(address indexed operator, uint256 tagId, address payToken, uint32 supply, uint256 unitShare);
    event TrimPrize(address indexed operator, uint256 tagId, address payToken);
    event ClaimPrize(address indexed recipient, uint256 tagId, uint256 units, address payToken, uint256 amount);

    event RefParamSet(address indexed operator, uint256 collectionId, uint256 level1, uint256 level2);

    event Referral(address indexed source, address indexed recipient, uint256 level, address payToken, uint256 amount);

    struct PrizePackage {
        uint32 supply; // 0 for unlimited
        uint32 rest;
        uint192 unitShare;
        address payToken;
    }

    address private constant NativeCurrency = address(0x0);
    address private constant zeroAddress = address(0x0);

    // tagId => prizeId[]
    mapping(uint256 => mapping(address => PrizePackage)) internal _tagPrizes;
    mapping(uint256 => EnumerableSet.AddressSet) internal _tagPrizeTokens;

    mapping(uint256 => uint256) internal _collectionRefParam; // collectionId=>fee

    IUnitagRelationRegistry public immutable relationRegistry;

    uint256 public constant PERCENTAGE_BASE = 10000;
    uint256 private constant FLAG_SET = 1 << 64;

    constructor(address relationRegistry_) {
        relationRegistry = IUnitagRelationRegistry(relationRegistry_);
        _collectionRefParam[0] = FLAG_SET | (150 << 32) | 350;
    }

    function _setRefParams(address operator, uint256 collectionId, uint256 level1, uint256 level2) internal {
        require(level1 + level2 <= PERCENTAGE_BASE, "UnitagPrizeDeposit: invalid L1 or L2 percentage");
        _collectionRefParam[collectionId] = FLAG_SET | (level2 << 32) | level1;
        emit RefParamSet(operator, collectionId, level1, level2);
    }

    function _refParams(uint256 collectionId) internal view returns (uint256 level1, uint256 level2) {
        uint256 refParams = _collectionRefParam[collectionId];
        if (refParams == 0) refParams = _collectionRefParam[0];
        level1 = refParams & type(uint32).max;
        level2 = (refParams >> 32) & type(uint32).max;
    }

    /**
     * @param collectionId the id of the collection
     * @param accounts  the accounts to set
     * @param signature the signatures of the accounts
     */
    function setParent(uint256 collectionId, address[] calldata accounts, bytes calldata signature) public {
        relationRegistry.setParent(collectionId, accounts, signature);
    }

    function _transferOutToken(address recipient, address payToken, uint256 value) private {
        if (payToken == NativeCurrency) {
            (bool success, ) = recipient.call{value: value}("");
            require(success, "Address: unable to send value, recipient may have reverted");
        } else IERC20(payToken).safeTransfer(recipient, value);
    }

    function transferOutTokenWithAncesors(uint256 collectionId, address recipient, address[] memory payTokens, uint256[] memory values) internal {
        address ancestors0;
        address ancestors1;
        (uint256 level1, uint256 level2) = _refParams(collectionId);
        {
            address[] memory ancestors = relationRegistry.ancestors(collectionId, recipient, 2);
            if (ancestors.length == 2) {
                ancestors0 = ancestors[0];
                ancestors1 = ancestors[1];
            } else if (ancestors.length == 1) {
                ancestors0 = ancestors[0];
                level2 = 0;
            } else {
                level1 = 0;
                level2 = 0;
            }
        }

        uint256 tokenCount = payTokens.length;
        for (uint256 index = 0; index < tokenCount; ++index) {
            uint256 value = values[index];
            address payToken = payTokens[index];
            uint256 feeTotal;
            if (level1 != 0) {
                uint256 fee = (value * level1) / PERCENTAGE_BASE;
                feeTotal += fee;
                _transferOutToken(ancestors0, payToken, fee);
                emit Referral(recipient, ancestors0, 1, payToken, fee);
            }
            if (level2 != 0) {
                uint256 fee = (value * level2) / PERCENTAGE_BASE;
                feeTotal += fee;
                _transferOutToken(ancestors1, payToken, fee);
                emit Referral(recipient, ancestors1, 2, payToken, fee);
            }
            _transferOutToken(recipient, payToken, value - feeTotal);
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
