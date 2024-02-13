// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUnitagRelationRegistry.sol";
import "./interfaces/IUnitagRefParamRegistry.sol";
import "./interfaces/IWETH9.sol";
import "./library/TransferHelper.sol"; 

contract UnitagRelationalPrizeDispatcherV3  {
    event Dispatch(address indexed recipient, address payToken, uint256 amount);
    event RefParamSet(address indexed operator, uint256 collectionId, uint256 feePercentage, uint256 level1, uint256 level2);
    event Referral(address indexed source, address indexed recipient, uint256 level, address payToken, uint256 amount);
    event Sweep(address indexed operator, address indexed recipient, address token, uint256 amount);

    uint256 public constant PERCENTAGE_BASE = 10000;
    address private constant zeroAddress = address(0x0);

    mapping(uint256 => uint256) internal _collectionRefParam; // collectionId=>fee

    IUnitagSimple public immutable unitag;
    IUnitagRelationRegistry public immutable relationRegistry;
    IUnitagRefParamRegistry public immutable refParamRegistry;
    IWETH9 public immutable weth9;

    constructor(address unitag_, address relationRegistry_, address refParamRegistry_, address weth9_) {
        unitag = IUnitagSimple(unitag_);
        weth9 = IWETH9(weth9_);
        relationRegistry = IUnitagRelationRegistry(relationRegistry_);
        refParamRegistry = IUnitagRefParamRegistry(refParamRegistry_);
    } 

    function dispatch(string calldata collectionName, address recipient, address payToken, uint256 value) public {
        (uint256 collectionId, , , ) = unitag.collectionByName(collectionName);
        dispatch(collectionId, recipient, payToken, value);
    }

    function dispatch(uint256 collectionId, address recipient, address payToken, uint256 value) public {
        (address[] memory accounts, uint256[] memory levels) = calculateTransfers(collectionId, recipient);
        for (uint256 idxAccount = 0; idxAccount < accounts.length; ++idxAccount) {
            uint256 outAmount = (value * levels[idxAccount]) / PERCENTAGE_BASE;
            TransferHelper.safeTransfer(payToken, accounts[idxAccount], outAmount);
            if (idxAccount == 0) emit Dispatch(recipient, payToken, outAmount);
            else emit Referral(recipient, accounts[idxAccount], idxAccount, payToken, outAmount);
        }
    }

    function dispatchBatch(uint256 collectionId, address recipient, address[] calldata payTokens, uint256[] calldata values) public {
        require(payTokens.length == values.length, "UnitagRelationalPrizeDispatcher: payTokens length != values length");
        (address[] memory accounts, uint256[] memory levels) = calculateTransfers(collectionId, recipient);
        uint256 accountLength = accounts.length;
        uint256 payTokensLength = payTokens.length;
        for (uint256 idxToken = 0; idxToken < payTokensLength; ++idxToken) {
            address payToken = payTokens[idxToken];
            for (uint256 idxAccount = 0; idxAccount < accountLength; ++idxAccount) {
                uint256 outAmount = (values[idxToken] * levels[idxAccount]) / PERCENTAGE_BASE;
                TransferHelper.safeTransfer(payToken, accounts[idxAccount], outAmount);
                if (idxAccount == 0) emit Dispatch(recipient, payToken, outAmount);
                else emit Referral(recipient, accounts[idxAccount], idxAccount, payToken, outAmount);
            }
        }
    }

    function dispatchFrom(string calldata collectionName, address recipient, address payToken, uint256 value) public {
        (uint256 collectionId, , , ) = unitag.collectionByName(collectionName);
        dispatchFrom(collectionId, recipient, payToken, value);
    }

    function dispatchFrom(uint256 collectionId, address recipient, address payToken, uint256 value) public {
        (address[] memory accounts, uint256[] memory levels) = calculateTransfers(collectionId, recipient);
        for (uint256 idxAccount = 0; idxAccount < accounts.length; ++idxAccount) {
            uint256 outAmount = (value * levels[idxAccount]) / PERCENTAGE_BASE;
            TransferHelper.safeTransferFrom(payToken, msg.sender, accounts[idxAccount], outAmount);
            if (idxAccount == 0) emit Dispatch(recipient, payToken, outAmount);
            else emit Referral(recipient, accounts[idxAccount], idxAccount, payToken, outAmount);
        }
    }

    function dispatchFromBatch(uint256 collectionId, address recipient, address[] calldata payTokens, uint256[] calldata values) public {
        require(payTokens.length == values.length, "UnitagRelationalPrizeDispatcher: payTokens length != values length");
        (address[] memory accounts, uint256[] memory levels) = calculateTransfers(collectionId, recipient);
        uint256 accountLength = accounts.length;
        uint256 payTokensLength = payTokens.length;
        for (uint256 idxToken = 0; idxToken < payTokensLength; ++idxToken) {
            address payToken = payTokens[idxToken];
            for (uint256 idxAccount = 0; idxAccount < accountLength; ++idxAccount) {
                uint256 outAmount = (values[idxToken] * levels[idxAccount]) / PERCENTAGE_BASE;
                TransferHelper.safeTransferFrom(payToken, msg.sender, accounts[idxAccount], outAmount);
                if (idxAccount == 0) emit Dispatch(recipient, payToken, outAmount);
                else emit Referral(recipient, accounts[idxAccount], idxAccount, payToken, outAmount);
            }
        }
    }

    function calculateTransfers(uint256 collectionId, address recipient) public view returns (address[] memory accounts, uint256[] memory levels) {
        accounts = new address[](3);
        levels = new uint256[](3);
        accounts[0] = recipient;
        levels[0] = PERCENTAGE_BASE;
        uint256[] memory refLevels = refParamRegistry.refParams(collectionId, 2);
        {
            address[] memory ancestors = relationRegistry.ancestors(collectionId, recipient, 2);
            uint256 index = 0;
            unchecked {
                for (; index < ancestors.length; ) {
                    address ancestor = ancestors[index];
                    uint256 level = refLevels[index];
                    if (ancestor != zeroAddress) {
                        ++index;
                        levels[0] -= level;
                        levels[index] = level;
                        accounts[index] = ancestor;
                    } else break;
                }
            }
            assembly {
                index := add(index, 1)
                mstore(accounts, index)
                mstore(levels, index)
            }
        }
    }

    function sweep(address tokenAddress, address recipient) external {
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance > 0) {
            TransferHelper.safeTransfer(tokenAddress, recipient, balance);
            emit Sweep(msg.sender, recipient, tokenAddress, balance);
        }
    }

    receive() external payable {
        weth9.deposit{value: msg.value}();
    }
}

interface IUnitagSimple {
    function collectionByName(string calldata collectionName) external view returns (uint256 collectionId, address owner, string memory name, string memory uri_);
}
