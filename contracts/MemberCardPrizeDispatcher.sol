// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "./interfaces/IUnitag.sol";
import "./interfaces/IERC1155SoulBond.sol";
import "./utils/SignerValidator.sol";
import "./library/UnitagLib.sol";

contract MemberCardPrizeDispatcher is Multicall, Ownable, ERC1155Receiver {
    using EnumerableSet for EnumerableSet.UintSet;
    using UnitagLib for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    event PrizeClaimed(address indexed to, uint256 indexed id, address payToken, uint256 tokenId, uint256 unitShare);
    event PrizeUpdated(address indexed operator, uint256 indexed id, uint256 indexed level, address payToken, uint256 tokenId, uint256 supply, uint256 unitShare);
    event PrizeOwnershipTransferred(uint256 indexed id, address indexed previousOwner, address indexed newOwner);

    struct PrizePackage {
        address owner;
        uint32 level;
        address payToken;
        uint32 supply;
        uint32 rest;
        uint256 unitShare;
        uint256 tokenId; // +1 for 1155, 0 for erc20
    }

    address public constant nativeCurrency = address(0x0);
    address constant zeroAddress = address(0x0);
    uint256 constant pointsPerLevel = 1000;

    IUnitag public unitag;
    IERC1155SoulBond public memberCardContract;
    uint256 public memberCardTokenId;
    // account => nonce
    mapping(address => uint256) public lastLevel;

    mapping(uint256 => EnumerableSet.UintSet) private _levelPrizes;
    mapping(uint256 => PrizePackage) public tokenPrizes;
    uint256 private _tokenPrizeIndex;

    constructor(
        address unitag_,
        address memberCardContract_,
        string memory collectionName
    ) {
        unitag = IUnitag(unitag_);
        memberCardContract = IERC1155SoulBond(memberCardContract_);
        (uint256 collectionId, address owner, , ) = unitag.collectionByName(collectionName);
        require(owner != zeroAddress, "UnitagPrizeDeposit: collection not exists");
        memberCardTokenId = collectionId;
    }

    function prizeOfLevel(uint256 level) external view returns (uint256[] memory prizeIds) {
        prizeIds = _levelPrizes[level].toArray();
    }

    function prizeOfLevelBatch(uint256[] calldata levels) external view returns (uint256[][] memory prizeIds) {
        prizeIds = new uint256[][](levels.length);
        for (uint256 index = 0; index < levels.length; ++index) prizeIds[index] = _levelPrizes[levels[index]].toArray();
    }

    function depositTokenPrize(
        uint32 level,
        address payToken,
        uint32 supply,
        uint256 unitShare
    ) external {
        uint256 income = _transferInToken(msg.sender, payToken, unitShare * supply);
        if (income > 0) {
            unitShare = income / supply;
            uint256 id = _tokenPrizeIndex;
            tokenPrizes[id].owner = msg.sender;
            tokenPrizes[id].level = level;
            tokenPrizes[id].payToken = payToken;
            tokenPrizes[id].supply = supply;
            tokenPrizes[id].rest = supply;
            tokenPrizes[id].unitShare = unitShare;
            _tokenPrizeIndex = id + 1;
            _levelPrizes[level].add(id);
            emit PrizeUpdated(msg.sender, id, level, payToken, 0, supply, unitShare);
        }
    }

    function refillTokenPrize(uint256 id, uint32 supply) external {
        require(tokenPrizes[id].owner == msg.sender, "require owner");
        uint256 income = _transferInToken(msg.sender, tokenPrizes[id].payToken, tokenPrizes[id].unitShare * supply);
        if (income > 0) {
            uint256 restToken = income + tokenPrizes[id].unitShare * tokenPrizes[id].rest;
            tokenPrizes[id].unitShare = restToken / (tokenPrizes[id].rest + supply);
            tokenPrizes[id].supply += supply;
            tokenPrizes[id].rest += supply;
            emit PrizeUpdated(msg.sender, id, tokenPrizes[id].level, tokenPrizes[id].payToken, 0, tokenPrizes[id].supply, tokenPrizes[id].unitShare);
        }
    }

    function changeOwner(uint256 id, address newOwner) external {
        require(tokenPrizes[id].owner == msg.sender, "UnitagPrizeDeposit: caller is not the owner");
        tokenPrizes[id].owner = newOwner;
        emit PrizeOwnershipTransferred(id, msg.sender, newOwner);
    }

    function retractPrize(uint256 id) external {
        require(tokenPrizes[id].owner == msg.sender, "UnitagPrizeDeposit: caller is not the owner");
        uint256 value = tokenPrizes[id].rest * tokenPrizes[id].unitShare;
        if (value > 0) {
            uint256 tokenId = tokenPrizes[id].tokenId;
            if (tokenId == 0) IERC20(tokenPrizes[id].payToken).safeTransfer(msg.sender, value);
            else IERC1155(tokenPrizes[id].payToken).safeTransferFrom(address(this), msg.sender, tokenId - 1, value, "");
        }
        tokenPrizes[id].rest = 0;
        _levelPrizes[tokenPrizes[id].level].remove(id);
        emit PrizeUpdated(msg.sender, id, tokenPrizes[id].level, tokenPrizes[id].payToken, tokenPrizes[id].tokenId, tokenPrizes[id].supply, tokenPrizes[id].unitShare);
    }

    function claim() external {
        uint256 bounds = memberCardContract.boundOf(msg.sender, memberCardTokenId);
        if (bounds > 0) {
            uint256 _lastLevel = lastLevel[msg.sender];
            uint256 currentLevel = bounds / pointsPerLevel;
            if (_lastLevel < currentLevel) {
                for (; _lastLevel++ < currentLevel; ) {
                    uint256[] memory prizeIds = _levelPrizes[_lastLevel].toArray();
                    for (uint256 index = 0; index < prizeIds.length; ++index) _claimImpl(msg.sender, prizeIds[index]);
                }
                lastLevel[msg.sender] = currentLevel;
            }
        }
    }

    function _claimImpl(address account, uint256 prizeId) private {
        uint256 tokenId = tokenPrizes[prizeId].tokenId;
        uint256 unitShare = tokenPrizes[prizeId].unitShare;
        address payToken = tokenPrizes[prizeId].payToken;
        uint256 rest = tokenPrizes[prizeId].rest - 1;
        if (tokenId == 0) IERC20(payToken).safeTransfer(account, unitShare);
        else IERC1155(payToken).safeTransferFrom(address(this), account, tokenId - 1, unitShare, "");
        tokenPrizes[prizeId].rest = uint32(rest);
        emit PrizeClaimed(account, prizeId, payToken, tokenId, unitShare);
        if (rest == 0) _levelPrizes[tokenPrizes[prizeId].level].remove(prizeId);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 tokenId,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        require(operator == from, "require self call");
        require(IERC165(msg.sender).supportsInterface(type(IERC1155).interfaceId), "UnitagPrizeDeposit: not a 1155 call");
        (uint256 route, bytes memory subData) = abi.decode(data, (uint256, bytes));
        if (route == 0) {
            (uint256 level, uint256 unitShare) = abi.decode(subData, (uint256, uint256));
            _depositERC1155(operator, level, msg.sender, tokenId, unitShare, uint32(value));
        } else if (route == 1) {
            uint256 prizeId = abi.decode(subData, (uint256));
            _refillERC1155(operator, tokenId, prizeId, uint32(value));
        } else revert("UnitagPrizeDeposit: unknow route");
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert("not supported");
    }

    function composeRoute0(uint256 level, uint256 unitShare) external pure returns (bytes memory) {
        return abi.encode(uint256(0), abi.encode(level, unitShare));
    }

    function composeRoute1(uint256 prizeId) external pure returns (bytes memory) {
        return abi.encode(uint256(1), abi.encode(prizeId));
    }

    function _refillERC1155(
        address operator,
        uint256 tokenId,
        uint256 id,
        uint32 value
    ) private {
        require(tokenId == tokenPrizes[id].tokenId + 1, "tokenId not equals");
        require(value % tokenPrizes[id].unitShare == 0, "UnitagPrizeDeposit: dispatch amount not equals");
        uint256 supply = value / tokenPrizes[id].unitShare;
        tokenPrizes[id].supply += uint32(supply);
        tokenPrizes[id].rest += uint32(supply);
        emit PrizeUpdated(operator, id, tokenPrizes[id].level, tokenPrizes[id].payToken, id, tokenPrizes[id].supply, tokenPrizes[id].unitShare);
    }

    function _depositERC1155(
        address operator,
        uint256 level,
        address payToken,
        uint256 tokenId,
        uint256 unitShare,
        uint32 value
    ) private {
        require(value % unitShare == 0, "UnitagPrizeDeposit: dispatch amount not equals");
        uint256 supply = value / unitShare;
        uint256 id = _tokenPrizeIndex;
        tokenPrizes[id].owner = operator;
        tokenPrizes[id].payToken = payToken;
        tokenPrizes[id].supply = uint32(supply);
        tokenPrizes[id].rest = uint32(supply);
        tokenPrizes[id].unitShare = unitShare;
        tokenPrizes[id].tokenId = tokenId + 1;
        _tokenPrizeIndex = id + 1;
        _levelPrizes[level].add(id);
        emit PrizeUpdated(operator, id, level, payToken, tokenId, value, unitShare);
    }

    function _transferInToken(
        address spender,
        address payToken,
        uint256 value
    ) private returns (uint256) {
        if (payToken == nativeCurrency) {
            if (msg.value < value) revert("UnitagPrizeDeposit: not enought deposit");
            return msg.value;
        } else {
            IERC20 erc20 = IERC20(payToken);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            IERC20(payToken).safeTransferFrom(spender, address(this), value);
            uint256 balanceAfter = erc20.balanceOf(address(this));
            return balanceAfter - balanceBefore;
        }
    }
}
