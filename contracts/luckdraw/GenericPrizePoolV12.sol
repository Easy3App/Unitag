// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TicketConsumer.sol";
import "../interfaces/IUnitagRelationalPrizeDispatcherV3.sol";
import "../interfaces/IWETH9.sol";
import "../interfaces/IUnitagMintable.sol";
import "../library/TransferHelper.sol";
import "../utils/SignerValidator.sol";
import "../utils/Multicall.sol";
import "../utils/SelfPermit.sol";

contract GenericPrizePoolV12 is Multicall, TicketConsumer, SelfPermit {
    using EnumerableSet for EnumerableSet.UintSet;

    address private constant ETH = address(0);
    uint8 private constant PRIZE_MODE_ERC20 = 0;
    uint8 private constant PRIZE_MODE_TAG = 1;
    uint256 private constant UINT96_MASK = type(uint96).max;

    event PoolCreated(uint256 indexed id, uint256 indexed collectionId, address indexed owner);
    event PrizeSynced(uint256 indexed id, address indexed operator, address indexed payToken, uint256 amount);
    event PrizeSweeped(uint256 indexed id, address indexed payToken, uint256 amount);
    event PoolEnabled(uint256 indexed id);
    event PoolEnded(uint256 indexed id);
    event Claimed(uint256 indexed id, address indexed claimer, uint256 orderId, uint256 nonce);

    struct LuckDrawPool {
        uint256 collectionId;
        address owner;
        uint8 status;
    }

    struct ClaimPackage {
        uint256 orderId;
        uint256[] tagIds;
        uint256[] tagValues;
        address[] payTokens;
        uint256[] values;
        bytes signature;
    }

    mapping(uint256 => mapping(address => uint256)) public prizes;
    mapping(uint256 => mapping(address => uint256)) public claimedPrizes;
    mapping(uint256 => LuckDrawPool) public pools;
    mapping(uint256 => mapping(address => uint256)) public claimNonce;

    IWETH9 public immutable weth9;
    IUnitagMintable public immutable unitag;
    IUnitagRelationalPrizeDispatcherV3 public immutable relationalDispatcher;

    constructor(address relationalDispatcher_, address unitag_, address weth9_, address signer_) TicketConsumer(signer_) {
        relationalDispatcher = IUnitagRelationalPrizeDispatcherV3(payable(relationalDispatcher_));
        unitag = IUnitagMintable(unitag_);
        weth9 = IWETH9(weth9_);
    }

    function createPool(uint256 id, uint256 collectionId) external {
        require(pools[id].owner == address(0), "LuckDraw: pool already exists");
        pools[id].owner = msg.sender;
        pools[id].collectionId = collectionId;
        emit PoolCreated(id, collectionId, msg.sender);
    }

    function syncTokenPrize(uint256 id, address payToken, uint256 newValue) external payable {
        require(pools[id].owner == msg.sender, "LuckDraw: not pool owner");
        uint256 oldValue = prizes[id][payToken];
        if (newValue == oldValue) return;
        if (newValue > oldValue) {
            uint256 value = _transferInToken(msg.sender, payToken, newValue - oldValue);
            increaseAllowance(payToken, value);
            newValue = oldValue + value;
        } else if (newValue < oldValue) {
            require(pools[id].status == 0, "LuckDraw: pool already enabled");
            uint256 value = oldValue - newValue;
            TransferHelper.safeTransfer(payToken, msg.sender, value);
            decreaseAllowance(payToken, value);
        }
        prizes[id][payToken] = newValue;
        emit PrizeSynced(id, msg.sender, payToken, newValue);
    }

    function enablePool(uint256 id) external {
        require(pools[id].owner == msg.sender, "LuckDraw: not pool owner");
        require(pools[id].status == 0, "LuckDraw: pool already enabled");
        pools[id].status = 1;
        emit PoolEnabled(id);
    }

    function endPool(uint256 id, address[] calldata payTokens, address to) external {
        require(pools[id].owner == msg.sender, "LuckDraw: not pool owner");
        pools[id].status = 2;
        emit PoolEnded(id);
        _sweepPool(id, payTokens, to);
    }

    function sweepPool(uint256 id, address[] calldata payTokens, address to) private {
        require(pools[id].owner == msg.sender, "LuckDraw: not pool owner");
        require(pools[id].status == 2, "LuckDraw: pool not ended");
        _sweepPool(id, payTokens, to);
    }

    function _sweepPool(uint256 id, address[] calldata payTokens, address to) private {
        uint256 length = payTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address payToken = payTokens[index];
            uint256 prize = prizes[id][payToken];
            uint256 value = prize - claimedPrizes[id][payToken];
            if (value > 0) {
                claimedPrizes[id][payToken] = prize;
                TransferHelper.safeTransfer(payToken, to, value);
                emit PrizeSweeped(id, payToken, value);
            }
        }
    }

    function claimPrize(uint256 id, ClaimPackage calldata claimPackage) external {
        require(pools[id].status == 1, "LuckDraw: pool not enabled");
        {
            uint256 nonce = _updateClaimNonce(id, msg.sender);
            bytes32 payload = keccak256(
                abi.encode(block.chainid, address(this), id, msg.sender, claimPackage.orderId, claimPackage.tagIds, claimPackage.tagValues, claimPackage.payTokens, claimPackage.values, nonce)
            );
            _validSignature(payload, claimPackage.signature);
            emit Claimed(id, msg.sender, claimPackage.orderId, nonce);
        }
        uint256 length = claimPackage.payTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address payToken = claimPackage.payTokens[index];
            uint256 value = claimPackage.values[index];
            {
                uint256 claimedPrize = claimedPrizes[id][payToken] + value;
                require(claimedPrize <= prizes[id][payToken], "LuckDraw: insufficient prize");
                claimedPrizes[id][payToken] = claimedPrize;
            }
            relationalDispatcher.dispatchFrom(pools[id].collectionId, msg.sender, payToken, value);
        }
        if (claimPackage.tagIds.length > 0) unitag.mintBatch(msg.sender, claimPackage.tagIds, claimPackage.tagValues, true);
    }

    /**
     * @dev update withdraw nonce
     */
    function _updateClaimNonce(uint256 id, address account) private returns (uint256) {
        uint256 nonce = claimNonce[id][account];
        claimNonce[id][account] = nonce + 1;
        return nonce;
    }

    function _transferInToken(address spender, address payToken, uint256 value) private returns (uint256) {
        if (msg.value > 0) {
            require(payToken == address(weth9), "LuckDraw: invalid weth address");
            weth9.deposit{value: msg.value}();
            return msg.value;
        } else {
            IERC20 erc20 = IERC20(payToken);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            TransferHelper.safeTransferFrom(payToken, spender, address(this), value);
            return erc20.balanceOf(address(this)) - balanceBefore;
        }
    }

    function increaseAllowance(address token, uint256 amount) private {
        uint256 allowance = IERC20(token).allowance(address(this), address(relationalDispatcher));
        TransferHelper.safeApprove(token, address(relationalDispatcher), amount + allowance);
    }

    function decreaseAllowance(address token, uint256 amount) private {
        uint256 allowance = IERC20(token).allowance(address(this), address(relationalDispatcher));
        TransferHelper.safeApprove(token, address(relationalDispatcher), allowance - amount);
    }
}
