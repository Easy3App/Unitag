// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IUnitagRelationalPrizeDispatcherV3.sol";
import "../interfaces/IWETH9.sol";
import "../library/TransferHelper.sol";
import "../utils/SignerValidator.sol";

contract UniTipMiningPoolV14 is SignerValidator, Ownable {
    address private constant ZERO_ADDRESS = address(0x0);
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant PERCENTAGE_BASE = 10000;
    uint256 private constant REF_PERCENTAGE_MAX = 1000;

    event PoolCreated(
        uint256 indexed id,
        address indexed owner,
        uint32 duration,
        uint32 startTime,
        address prizeToken,
        uint16 likeFactor,
        uint16 retweetFactor,
        uint16 replyFactor,
        uint16 quoteFactor,
        uint16 impressionFactor,
        uint256 prizeValue,
        string keywords,
        string hashTag
    );
    event RefUpdated(uint256 indexed id, address indexed operator, address refAccount, uint16 refPercentage);
    event PoolEndTimeUpdated(uint256 indexed id, address indexed operator, uint32 duration, uint32 endTime);
    event PoolUpdated(uint256 indexed id, address indexed operator, uint16 likeFactor, uint16 retweetFactor, uint16 replyFactor, uint16 quoteFactor, uint16 impressionFactor);
    event PoolCharged(uint256 indexed id, address indexed operator, uint256 prizeValue, uint256 amount);
    event PoolDischarged(uint256 indexed id, address indexed operator, uint256 amount);
    event PoolEnabled(uint256 indexed id, uint32 startTime, uint32 endTime);
    event Claim(address indexed claimer, uint256 indexed id, uint256 claimedValue);
    event ClaimRef(address indexed claimer, uint256 indexed id, uint256 claimedValue);
    event EmergencyWithdraw(address indexed owner, uint256 indexed id);
    event SweepPool(address indexed operator, uint256 indexed id, address to, address token, uint256 value);
    event SweepDelayChanged(address indexed operator, uint256 sweepDelay);

    struct UniTipPool {
        address owner;
        uint32 endTime;
        uint32 duration;
        uint32 startTime;
        //======================256bit//
        address prizeToken;
        //======================160bit//
        uint256 prizeValue;
        //======================256bit//
        uint256 paidValue;
        //======================256bit//
        uint256 claimed;
        //======================256bit//
        address refAccount;
        uint16 actualPercentage;
        mapping(address => uint256) charges;
    }

    struct UniTipPoolCreationData {
        uint32 duration;
        uint32 startTime;
        address prizeToken;
        uint16 likeFactor;
        uint16 retweetFactor;
        uint16 replyFactor;
        uint16 quoteFactor;
        uint16 impressionFactor;
        uint256 prizeValue;
        string keywords;
        string hashTag;
    }

    mapping(uint256 => UniTipPool) public uniTipPools;
    mapping(uint256 => mapping(address => uint256)) public claimed;

    uint32 public idCounter;
    uint32 public sweepDelay = uint32(SECONDS_PER_DAY * 7);

    IWETH9 public immutable weth9;
    IUnitagRelationalPrizeDispatcherV3 public immutable relationalDispatcher;
    uint256 public immutable collectionId;

    constructor(address relationalDispatcher_, address weth9_, address signer_, uint256 collectionId_) SignerValidator(signer_) {
        relationalDispatcher = IUnitagRelationalPrizeDispatcherV3(payable(relationalDispatcher_));
        weth9 = IWETH9(weth9_);
        collectionId = collectionId_;
    }

    function setSweepDelay(uint256 sweepDelay_) external onlyOwner {
        require(sweepDelay_ >= SECONDS_PER_DAY * 7, "sweepDelay < 7 days");
        sweepDelay = uint32(sweepDelay_);
        emit SweepDelayChanged(msg.sender, sweepDelay_);
    }

    function createPool(UniTipPoolCreationData memory poolData) public payable onlyOwner returns (uint256 id) {
        if (poolData.startTime < block.timestamp) poolData.startTime = uint32(block.timestamp);
        else require(poolData.startTime >= block.timestamp, "startTime <  now");
        require(poolData.duration >= SECONDS_PER_DAY, "duration <= 1 day");
        require(poolData.duration <= SECONDS_PER_DAY * 10, "duration > 10 days");
        if (poolData.prizeToken == ZERO_ADDRESS) poolData.prizeToken = address(weth9);
        id = idCounter;
        idCounter = uint32(id + 1);
        uniTipPools[id].owner = msg.sender;
        uniTipPools[id].startTime = poolData.startTime;
        uniTipPools[id].duration = poolData.duration;
        uniTipPools[id].prizeToken = poolData.prizeToken;
        uniTipPools[id].prizeValue = poolData.prizeValue;
        uniTipPools[id].actualPercentage = uint16(PERCENTAGE_BASE);
        emit PoolCreated(
            id,
            msg.sender,
            poolData.duration,
            poolData.startTime,
            poolData.prizeToken,
            poolData.likeFactor,
            poolData.retweetFactor,
            poolData.replyFactor,
            poolData.quoteFactor,
            poolData.impressionFactor,
            poolData.prizeValue,
            poolData.keywords,
            poolData.hashTag
        );
    }

    function createPoolAndPay(UniTipPoolCreationData memory poolData) external payable onlyOwner {
        uint256 id = createPool(poolData);
        chargePool(id, poolData.prizeValue);
    }

    function modifyPoolFactors(uint256 id, uint16 likeFactor, uint16 retweetFactor, uint16 replyFactor, uint16 quoteFactor, uint16 impressionFactor) external beforeDispatching(id) {
        require(uniTipPools[id].owner == msg.sender, "not owner");
        emit PoolUpdated(id, msg.sender, likeFactor, retweetFactor, replyFactor, quoteFactor, impressionFactor);
    }

    function modifyPoolRefAccount(uint256 id, address refAccount, uint256 refPercentage) external beforeDispatching(id) onlyOwner {
        require(refPercentage <= REF_PERCENTAGE_MAX, "invalid refPercentage");
        require(refAccount != address(0), "invalid refAccount");
        uniTipPools[id].refAccount = refAccount;
        uniTipPools[id].actualPercentage = uint16(PERCENTAGE_BASE - refPercentage);
        emit RefUpdated(id, msg.sender, refAccount, uint16(refPercentage));
    }

    function modifyPoolEndTime(uint256 id, uint256 prolonged) external beforeDispatching(id) onlyOwner {
        uint256 endTime = uniTipPools[id].endTime;
        require(endTime > 0, "pool not enabled");
        require(endTime < block.timestamp + SECONDS_PER_DAY * 10, "current endTime > 10 days");
        require(prolonged <= SECONDS_PER_DAY * 10, "prolonged > 10 days");
        endTime += prolonged;
        uniTipPools[id].duration += uint32(prolonged);
        uniTipPools[id].endTime = uint32(endTime);
        emit PoolEndTimeUpdated(id, msg.sender, uniTipPools[id].duration, uniTipPools[id].endTime);
    }

    function charges(uint256 id, address account) external view returns (uint256) {
        return uniTipPools[id].charges[account];
    }

    function chargePool(uint256 id, uint256 value) public payable beforeDispatching(id) {
        (address payToken, uint256 amount) = _transferInToken(msg.sender, uniTipPools[id].prizeToken, value);
        require(payToken == uniTipPools[id].prizeToken, "wrong token");
        increaseAllowance(payToken, amount);
        uint256 paidValue = uniTipPools[id].paidValue + amount;
        if (paidValue >= uniTipPools[id].prizeValue) {
            if (uniTipPools[id].endTime == 0) {
                uint256 startTime = uniTipPools[id].startTime;
                if (startTime < block.timestamp) {
                    startTime = block.timestamp;
                    uniTipPools[id].startTime = uint32(startTime);
                }
                uint256 endTime = startTime + uniTipPools[id].duration;
                uniTipPools[id].endTime = uint32(endTime);
                emit PoolEnabled(id, uint32(startTime), uint32(endTime));
            }
            if (paidValue > uniTipPools[id].prizeValue) {
                uniTipPools[id].prizeValue = paidValue;
            }
        }
        uniTipPools[id].paidValue = paidValue;
        uniTipPools[id].charges[msg.sender] += amount;
        emit PoolCharged(id, msg.sender, uniTipPools[id].prizeValue, amount);
    }

    function dischargePool(uint256 id, uint256 value) public notEnabled(id) {
        require(uniTipPools[id].charges[msg.sender] >= value, "not enough charged");
        uniTipPools[id].charges[msg.sender] -= value;
        uniTipPools[id].paidValue -= value;
        address prizeToken = uniTipPools[id].prizeToken;
        TransferHelper.safeTransfer(prizeToken, msg.sender, value);
        decreaseAllowance(prizeToken, value);
        emit PoolDischarged(id, msg.sender, value);
    }

    function emergencyWithdraw(uint256 id, bytes memory signature) external beforeDispatching(id) {
        require(uniTipPools[id].owner == msg.sender, "not owner");
        bytes32 msgHash = keccak256(abi.encodePacked(block.chainid, address(this), msg.sender, id));
        _validSignature(msgHash, signature);

        address payToken = uniTipPools[id].prizeToken;
        uint256 value = uniTipPools[id].prizeValue;
        decreaseAllowance(payToken, value);
        TransferHelper.safeTransfer(payToken, msg.sender, value);
        uniTipPools[id].prizeValue = 0;
        emit EmergencyWithdraw(msg.sender, id);
    }

    function claim(uint256 id, address account, uint256 totalFactor, uint256 factor, bytes memory signature) public dispatching(id) {
        require(claimed[id][account] == 0, "already claimed");
        bytes32 msgHash = keccak256(abi.encodePacked(block.chainid, address(this), id, account, totalFactor, factor));
        _validSignature(msgHash, signature);
        uint256 paid = (uniTipPools[id].prizeValue * uniTipPools[id].actualPercentage * factor) / (totalFactor * PERCENTAGE_BASE);
        claimed[id][account] = paid;
        uniTipPools[id].claimed += paid;
        address payToken = uniTipPools[id].prizeToken;
        relationalDispatcher.dispatchFrom(collectionId, account, payToken, paid);
        emit Claim(account, id, paid);
    }

    function claimBatch(uint256[] memory ids, address account, uint256[] memory totalFactors, uint256[] memory factors, bytes memory signature) public {
        uint256 length = ids.length;
        require(length == totalFactors.length && length == factors.length, "length not match");
        _validSignature(keccak256(abi.encodePacked(block.chainid, address(this), ids, account, totalFactors, factors)), signature);

        address[] memory payTokens = new address[](length);
        uint256[] memory values = new uint256[](length);
        uint256 lengthPayTokens;
        for (uint256 index = 0; index < length; ++index) {
            uint256 id = ids[index];
            {
                uint256 endTime = uniTipPools[id].endTime;
                require(endTime + sweepDelay >= block.timestamp && endTime < block.timestamp, "pool closed");
            }
            require(claimed[id][account] == 0, "already claimed");
            uint256 paid = (uniTipPools[id].prizeValue * uniTipPools[id].actualPercentage * factors[index]) / (totalFactors[index] * PERCENTAGE_BASE);
            if (paid > 0) {
                claimed[id][account] = paid;
                uniTipPools[id].claimed += paid;
                require(uniTipPools[id].claimed <= uniTipPools[id].prizeValue, "claim overflow");
                address payToken = uniTipPools[id].prizeToken;
                for (uint256 index2 = 0; index2 < lengthPayTokens; ++index2) {
                    if (payToken == payTokens[index2]) {
                        values[index2] += paid;
                        paid = 0;
                    }
                }
                if (paid > 0) {
                    payTokens[lengthPayTokens] = payToken;
                    values[lengthPayTokens] = paid;
                    ++lengthPayTokens;
                }
            }
            emit Claim(account, id, paid);
        }
        if (lengthPayTokens > 0) {
            if (lengthPayTokens != payTokens.length) {
                assembly {
                    mstore(payTokens, lengthPayTokens)
                    mstore(values, lengthPayTokens)
                }
            }
            relationalDispatcher.dispatchFromBatch(collectionId, account, payTokens, values);
        }
    }

    function claimRef(uint256 id) external dispatching(id) {
        address refAccount = uniTipPools[id].refAccount;
        require(refAccount != ZERO_ADDRESS && refAccount == msg.sender, "not set or already claimed");

        uint256 paid = (uniTipPools[id].prizeValue * (PERCENTAGE_BASE - uniTipPools[id].actualPercentage)) / PERCENTAGE_BASE;
        uniTipPools[id].claimed += paid;
        uniTipPools[id].refAccount = ZERO_ADDRESS;
        address payToken = uniTipPools[id].prizeToken;
        relationalDispatcher.dispatchFrom(collectionId, msg.sender, payToken, paid);
        emit ClaimRef(msg.sender, id, paid);
    }

    function sweepPool(uint256 id, address to) external onlyOwner ended(id) {
        require(uniTipPools[id].owner != address(0), "not valid pool");
        address payToken = uniTipPools[id].prizeToken;
        uint256 value = uniTipPools[id].prizeValue - uniTipPools[id].claimed;
        decreaseAllowance(payToken, value);
        TransferHelper.safeTransfer(uniTipPools[id].prizeToken, to, value);
        uniTipPools[id].claimed = uniTipPools[id].prizeValue;
        emit SweepPool(msg.sender, id, to, uniTipPools[id].prizeToken, value);
    }

    function _transferInToken(address spender, address payToken, uint256 value) private returns (address, uint256) {
        if (msg.value > 0) {
            weth9.deposit{value: msg.value}();
            return (address(weth9), msg.value);
        } else {
            IERC20 erc20 = IERC20(payToken);
            uint256 balanceBefore = erc20.balanceOf(address(this));
            TransferHelper.safeTransferFrom(payToken, spender, address(this), value);
            return (payToken, erc20.balanceOf(address(this)) - balanceBefore);
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

    function setSigner(address signer_) external onlyOwner {
        _setRemoteSigner(signer_);
    }

    modifier notEnabled(uint256 id) {
        require(uniTipPools[id].owner != ZERO_ADDRESS, "pool not exist");
        require(uniTipPools[id].endTime == 0, "pool enabled");
        _;
    }

    modifier beforeDispatching(uint256 id) {
        require(uniTipPools[id].owner != ZERO_ADDRESS, "pool not exist");
        uint256 endTime = uniTipPools[id].endTime;
        require(endTime == 0 || endTime > block.timestamp, "pool not dispatchable");
        _;
    }

    modifier dispatching(uint256 id) {
        require(uniTipPools[id].owner != ZERO_ADDRESS, "pool not exist");
        uint256 endTime = uniTipPools[id].endTime;
        require(endTime > 0, "pool not enabled");
        require(endTime <= block.timestamp && endTime + sweepDelay > block.timestamp, "pool closed");
        _;
    }

    modifier ended(uint256 id) {
        require(uniTipPools[id].owner != ZERO_ADDRESS, "pool not exist");
        uint256 endTime = uniTipPools[id].endTime;
        require(endTime > 0 && endTime + sweepDelay <= block.timestamp, "pool not closed");
        _;
    }
}
