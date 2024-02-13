// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./utils/Multicall.sol";
import "./library/TransferHelper.sol";
import "./interfaces/IUnitagRelationalPrizeDispatcherV2.sol";
import "./interfaces/IWETH9.sol";

abstract contract PrizeDepositStorageV3 is Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;

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

    address private constant NATIVE_CURRENCY = address(0x0);

    // tagId => prizeId[]
    mapping(uint256 => mapping(address => PrizePackage)) internal _tagPrizes;
    mapping(uint256 => EnumerableSet.AddressSet) internal _tagPrizeTokens;

    mapping(uint256 => uint256) internal _collectionRefParam; // collectionId=>fee

    // project=>token=>rest
    mapping(uint256 => mapping(address => uint256)) internal _prizePool;

    IWETH9 public immutable weth9;
    IUnitagRelationalPrizeDispatcherV2 public immutable relationalDispatcher;

    constructor(address relationalDispatcher_, address weth9_) {
        relationalDispatcher = IUnitagRelationalPrizeDispatcherV2(payable(relationalDispatcher_));
        weth9 = IWETH9(weth9_);
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
        (payToken, amount) = _transferInToken(sender, payToken, amount);
        _tagPrizeTokens[collectionId].add(payToken);
        _prizePool[collectionId][payToken] += amount;
        emit DepositPrize(sender, collectionId, payToken, amount);
    }

    function _withdrawPrize(address recipient, uint256 collectionId, address payToken, uint256 amount) internal {
        uint256 balance = _prizePool[collectionId][payToken];
        require(balance >= amount, "UnitagPrizeDeposit: not enought prize");
        _prizePool[collectionId][payToken] = balance - amount;
        TransferHelper.safeTransfer(payToken, recipient, amount);
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
                    emit ClaimPrize(recipient, tagId, _units, payToken, amount);
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
            relationalDispatcher.dispatchBatch(collectionId, recipient, payTokens, payAmounts);
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
        relationalDispatcher.setParent(collectionId, accounts, signature);
    }

    function _transferInToken(address spender, address payToken, uint256 value) private returns (address, uint256) {
        if (payToken == NATIVE_CURRENCY) {
            weth9.deposit{value: msg.value}();
            return (address(weth9), msg.value);
        } else {
            IERC20 erc20 = IERC20(payToken);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            TransferHelper.safeTransferFrom(payToken, spender, address(this), value);
            return (payToken, erc20.balanceOf(address(this)) - balanceBefore);
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
