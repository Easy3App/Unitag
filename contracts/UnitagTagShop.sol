// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUnitag.sol";
import "./library/UnitagLib.sol";

contract UnitagTagShop {
    using SafeERC20 for IERC20;

    event TagPlanUpdated(
        uint256 indexed tagId,
        address payToken,
        uint32 supply,
        uint32 rest,
        uint8 maxPurchaseOnce,
        uint8 maxPurchasePerAccount,
        bool bindImmediately,
        uint256 unitPrice,
        address payReciver
    );
    event TagPlanPurchased(address indexed buyer, uint256 indexed tagId, uint32 amount);
    event Mint(address indexed operator, address indexed to, uint256 tagId, uint256 amount, bool bindImmediately);
    event MintBatch(address indexed operator, address indexed to, uint256[] tagIds, uint256[] amounts, bool bindImmediately);

    address public constant nativeCurrency = address(0x0);

    IUnitag public unitag;
    bytes32 private _payloadPrefix;

    struct TagPlan {
        address payToken;
        uint32 supply; // 0 for unlimited
        uint32 rest;
        address payReciver;
        uint32 maxPurchaseOnce; // 0 for not started
        uint32 maxPurchasePerAccount; // 0 for unlimited
        bool bindImmediately;
        uint256 unitPrice;
    }

    // tagId => account => count
    mapping(uint256 => mapping(address => uint256)) public planPurchased;
    mapping(uint256 => TagPlan) public tagPlan;

    // account => nonce
    mapping(address => uint256) public nonces;

    constructor(address unitag_) {
        unitag = IUnitag(unitag_);
    }

    function setupTagPrice(
        string calldata tagFullName,
        address payToken,
        uint32 supply,
        uint8 maxPurchaseOnce,
        uint8 maxPurchasePerAccount,
        bool bindImmediately,
        uint256 unitPrice,
        address payReciver
    ) external {
        uint256 tagId = _validTagOwner(tagFullName, msg.sender);
        tagPlan[tagId].payToken = payToken;
        tagPlan[tagId].supply = supply;
        tagPlan[tagId].rest = supply;
        tagPlan[tagId].maxPurchaseOnce = maxPurchaseOnce;
        tagPlan[tagId].maxPurchasePerAccount = maxPurchasePerAccount;
        tagPlan[tagId].unitPrice = unitPrice;
        tagPlan[tagId].payReciver = payReciver;
        tagPlan[tagId].bindImmediately = bindImmediately;
        emit TagPlanUpdated(tagId, payToken, supply, supply, maxPurchaseOnce, maxPurchasePerAccount, bindImmediately, unitPrice, payReciver);
    }

    function purchase(string calldata tagFullName, uint32 amount) external payable {
        uint256 tagId = UnitagLib.tagFullNameToId(tagFullName);
        _purchaseImpl(tagId, msg.sender, amount);
        unitag.mint(msg.sender, tagId, amount, true);
    }

    function _purchaseImpl(
        uint256 tagId,
        address account,
        uint32 amount
    ) private {
        TagPlan memory targetPlan = tagPlan[tagId];
        require(targetPlan.unitPrice > 0, "Not saleable");
        require(targetPlan.maxPurchaseOnce >= amount, "reach max purchase per transaction");
        if (targetPlan.maxPurchasePerAccount > 0) {
            uint256 purchased = planPurchased[tagId][account] + amount;
            require(purchased <= targetPlan.maxPurchasePerAccount, "exceed max purchase per account");
            planPurchased[tagId][account] = purchased;
        }
        require(targetPlan.rest >= amount, "supply not enought");
        tagPlan[tagId].rest = targetPlan.rest - amount;
        _transferToken(targetPlan.payToken, amount * targetPlan.unitPrice, account, targetPlan.payReciver);
        emit TagPlanPurchased(account, tagId, amount);
    }

    function _transferToken(
        address contractAddress,
        uint256 amount,
        address spender,
        address reciver
    ) private {
        if (contractAddress == nativeCurrency) {
            if (msg.value != amount) {
                if (msg.value > amount) Address.sendValue(payable(spender), msg.value - amount);
                else revert("not enought payed");
            }
            Address.sendValue(payable(spender), amount);
        } else {
            IERC20 erc20 = IERC20(contractAddress);
            erc20.safeTransferFrom(spender, reciver, amount);
            if (msg.value > 0) Address.sendValue(payable(spender), msg.value);
        }
    }

    function _validTagOwner(string calldata tagFullName, address account) private view returns (uint256 tagId) {
        tagId = UnitagLib.tagFullNameToId(tagFullName);
        (uint256 collectionId, , ) = unitag.tagById(tagId);
        (address owner, , ) = unitag.collectionById(collectionId);
        require(owner == account, "owner is not valid");
    }
}
