// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUnitagRelationRegistry.sol";

abstract contract PrizeDepositStorageV2 is Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    event DepositPrize(address indexed sender, uint256 indexed collectionId, address indexed payToken, uint256 amount);
    event WithdrawPrize(address indexed sender, uint256 indexed collectionId, address indexed payToken, uint256 amount);
    event SetupPrize(address indexed operator, uint256 tagId, address payToken, uint32 supply, uint256 unitShare);
    event TrimPrize(address indexed operator, uint256 tagId, address payToken);
    event ClaimPrize(address indexed recipient, uint256 tagId, uint256 units, address payToken, uint256 amount);
    event RefParamSet(address indexed operator, uint256 collectionId, uint256 feePercentage, uint256 level1, uint256 level2);
    event Referral(address indexed source, address indexed recipient, uint256 level, address payToken, uint256 amount);

    struct PrizePackage {
        uint32 supply; // 0 for unlimited
        uint32 rest;
        uint192 unitShare;
        address payToken;
    }

    address private constant nativeCurrency = address(0x0);
    address private constant zeroAddress = address(0x0);

    // tagId => prizeId[]
    mapping(uint256 => mapping(address => PrizePackage)) internal _tagPrizes;
    mapping(uint256 => EnumerableSet.AddressSet) internal _tagPrizeTokens;

    mapping(uint256 => uint256) internal _collectionRefParam; // collectionId=>fee

    // project=>token=>rest
    mapping(uint256 => mapping(address => uint256)) internal _prizePool;
    IUnitagRelationRegistry public immutable relationRegistry;

    uint256 public constant PERCENTAGE_BASE = 10000;

    constructor(address relationRegistry_) {
        relationRegistry = IUnitagRelationRegistry(relationRegistry_);
    }

    function _setRefParams(address operator, uint256 collectionId, uint256 feePercentage, uint256 level1, uint256 level2) internal {
        require(feePercentage <= PERCENTAGE_BASE, "UnitagPrizeDeposit: invalid ref level");
        require(level1 <= PERCENTAGE_BASE, "UnitagPrizeDeposit: invalid L1 percentage");
        require(level2 <= PERCENTAGE_BASE, "UnitagPrizeDeposit: invalid L2 percentage");
        require(level1 + level2 <= PERCENTAGE_BASE, "UnitagPrizeDeposit: invalid L1+L2 percentage");
        _collectionRefParam[collectionId] = (feePercentage << 64) | (level2 << 32) | level1;
        emit RefParamSet(operator, collectionId, feePercentage, level1, level2);
    }

    function _refParams(uint256 collectionId) internal view returns (uint256 feePercentage, uint256 level1, uint256 level2) {
        uint256 refParams = _collectionRefParam[collectionId];
        level1 = refParams & type(uint32).max;
        level2 = (refParams >> 32) & type(uint32).max;
        feePercentage = refParams >> 64;
    }

    function _prizePoolOf(uint256 collectionId, address token) internal view returns (uint256) {
        return _prizePool[collectionId][token];
    }

    function _prizeOf(uint256 tagId) internal view returns (PrizePackage[] memory prizes) {
        EnumerableSet.AddressSet storage prizeTokens = _tagPrizeTokens[tagId];
        uint256 prizeCount = prizeTokens.length();
        prizes = new PrizePackage[](prizeCount);
        mapping(address => PrizePackage) storage _prizes = _tagPrizes[tagId];
        for (uint256 index = 0; index < prizeCount; ++index) {
            address payToken = prizeTokens.at(index);
            prizes[index] = _prizes[payToken];
            prizes[index].payToken = payToken;
        }
    }

    function _depositPrize(address sender, uint256 collectionId, address payToken, uint256 amount) internal {
        uint256 balance = _transferInToken(sender, payToken, amount);
        _prizePool[collectionId][payToken] += balance;
        emit DepositPrize(sender, collectionId, payToken, balance);
    }

    function _withdrawPrize(address recipient, uint256 collectionId, address payToken, uint256 amount) internal {
        uint256 balance = _prizePool[collectionId][payToken];
        require(balance >= amount, "UnitagPrizeDeposit: not enought prize");
        _prizePool[collectionId][payToken] = balance - amount;
        _transferOutToken(recipient, payToken, amount);
        emit WithdrawPrize(recipient, collectionId, payToken, amount);
    }

    function _setupPrize(address operator, uint256 tagId, address payToken, uint32 supply, uint192 unitShare) internal {
        if (unitShare == 0) _tagPrizeTokens[tagId].remove(payToken);
        else {
            _tagPrizeTokens[tagId].add(payToken);
            PrizePackage storage prize = _tagPrizes[tagId][payToken];
            prize.supply = supply;
            prize.rest = supply;
            prize.unitShare = unitShare;
            prize.payToken = payToken;
        }
        emit SetupPrize(operator, tagId, payToken, supply, unitShare);
    }

    function _claimPrize(address recipient, uint256 collectionId, uint256 tagId, uint256 amount) internal {
        uint256 prizeCount = _tagPrizeTokens[tagId].length();
        address[] memory payTokens = new address[](prizeCount);
        uint256[] memory payAmounts = new uint256[](prizeCount);
        uint256[] memory units = new uint256[](prizeCount);
        uint256 rCount;
        for (uint256 index = 0; index < prizeCount; ++index) {
            address payToken = _tagPrizeTokens[tagId].at(index);
            {
                PrizePackage storage prize = _tagPrizes[tagId][payToken];
                uint256 balance = _prizePool[collectionId][payToken];
                {
                    uint256 _units = amount;
                    uint256 unitShare = prize.unitShare;
                    if (balance < unitShare) continue;
                    if (prize.supply > 0) {
                        uint256 rest = prize.rest;
                        _units = _min(rest, amount);
                        if (_units == 0) continue;
                        prize.rest = uint32(rest - _units);
                    }
                    _units = _min(balance / unitShare, _units);

                    uint256 sendAmount = _units * unitShare;
                    balance -= sendAmount;

                    payTokens[rCount] = payToken;
                    payAmounts[rCount] = sendAmount;
                    units[rCount] = _units;
                }
                _prizePool[collectionId][payToken] = balance;
                ++rCount;
            }
        }
        if (rCount > 0) {
            if (rCount != payTokens.length) {
                assembly {
                    mstore(payTokens, rCount)
                    mstore(payAmounts, rCount)
                    mstore(units, rCount)
                }
            }
            _transferOutTokenWithAncesors(collectionId, recipient, tagId, units, payTokens, payAmounts);
        }
    }

    function trimPrize(uint256 tagId) public {
        mapping(address => PrizePackage) storage prizes = _tagPrizes[tagId];
        EnumerableSet.AddressSet storage prizeTokens = _tagPrizeTokens[tagId];
        uint256 prizeCount = prizeTokens.length();
        for (uint256 index = 0; index < prizeCount; ) {
            address prizeToken = prizeTokens.at(index);
            if (prizes[prizeToken].supply > 0 && prizes[prizeToken].rest == 0) {
                --prizeCount;
                prizeTokens.remove(prizeToken);
                emit TrimPrize(msg.sender, tagId, prizeToken);
            } else ++index;
        }
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
        if (payToken == nativeCurrency) {
            (bool success, ) = recipient.call{value: value}("");
            require(success, "Address: unable to send value, recipient may have reverted");
        } else IERC20(payToken).safeTransfer(recipient, value);
    }

    function _transferOutTokenWithAncesors(uint256 collectionId, address recipient, uint256 tagId, uint256[] memory units, address[] memory payTokens, uint256[] memory values) private {
        address ancestors0;
        address ancestors1;
        (, uint256 level1, uint256 level2) = _refParams(collectionId);
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
            emit ClaimPrize(recipient, tagId, units[index], payToken, value - feeTotal);
        }
    }

    function _transferInToken(address spender, address payToken, uint256 value) private returns (uint256) {
        if (payToken == nativeCurrency) {
            return msg.value;
        } else {
            IERC20 erc20 = IERC20(payToken);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            IERC20(payToken).safeTransferFrom(spender, address(this), value);
            return erc20.balanceOf(address(this)) - balanceBefore;
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
