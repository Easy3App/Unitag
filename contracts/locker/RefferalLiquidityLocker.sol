// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "../refferal/RefferalDispatcher.sol";
import "../interfaces/INonfungiblePosition.sol";
import "../interfaces/IUnitag.sol";

contract RefferalLiquidityLocker is IERC721Receiver, RefferalDispatcher, Ownable {
    event Deposit(address indexed sender, uint256 indexed tokenId, address token0, address token1, uint256 fee, uint256 liquidity);
    event TokenLocked(address indexed operator, uint256 indexed tokenId, uint256 unlockTime);
    event Withdraw(address indexed reciver, uint256 indexed tokenId);
    event CollectFees(address indexed operator, address indexed reciver, uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    address public immutable uniswapV3PositionsNFT;
    uint256 public immutable collectionId;

    // releaseTime<<160 | owner
    mapping(uint256 => uint256) private _tokenData;

    constructor(address uniswapV3PositionsNFT_, address relationRegistry_, uint256 collectionId_) RefferalDispatcher(relationRegistry_) {
        uniswapV3PositionsNFT = uniswapV3PositionsNFT_;
        collectionId = collectionId_;
    }

    function setRefParams(uint256 level1, uint256 level2) external onlyOwner {
        _setRefParams(msg.sender, collectionId, level1, level2);
    }

    function refParams() public view returns (uint256 level1, uint256 level2) {
        return _refParams(collectionId);
    }

    function collectFeeRefferal(uint256 tokenId) external {
        (address owner, ) = lockInfoOf(tokenId);
        require(owner != address(0x0), "token not exists");
        _collectFeesByTokenIdRefferal(tokenId, owner);
    }

    function collectFee(uint256 tokenId) external {
        (address owner, ) = lockInfoOf(tokenId);
        require(owner != address(0x0), "token not exists");
        _collectFeesByTokenId(tokenId, owner);
    }

    function infoOf(uint256 tokenId) public view returns (address owner, uint256 restTime, uint256 liquidity, address token0, address token1, uint256 fee, string memory metadata) {
        INonfungiblePosition nft = INonfungiblePosition(uniswapV3PositionsNFT);
        (, , token0, token1, fee, , , liquidity, , , , ) = nft.positions(tokenId);
        (owner, restTime) = lockInfoOf(tokenId);
        if (restTime > block.timestamp) restTime -= block.timestamp;
        else restTime = 0;
        metadata = nft.tokenURI(tokenId);
    }

    function lockInfoOf(uint256 tokenId) public view returns (address owner, uint256 releaseTime) {
        uint256 data = _tokenData[tokenId];
        owner = address(uint160(data & (type(uint160).max)));
        releaseTime = data >> 160;
    }

    function emergencyWithdrawDEV(uint256 tokenId, address recipient) external onlyOwner {
        IERC721(uniswapV3PositionsNFT).safeTransferFrom(address(this), recipient, tokenId);
        delete _tokenData[tokenId];
    }

    function deposit(uint256 tokenId) external {
        IERC721(uniswapV3PositionsNFT).safeTransferFrom(msg.sender, address(this), tokenId);
    }

    function withdraw(uint256 tokenId) external {
        (address owner, uint256 releaseTime) = lockInfoOf(tokenId);
        delete _tokenData[tokenId];
        require(owner == msg.sender, "require token owner");
        require(releaseTime <= block.timestamp, "still in lock");
        IERC721(uniswapV3PositionsNFT).safeTransferFrom(address(this), owner, tokenId);
        emit Withdraw(owner, tokenId);
    }

    function postpone(uint256 tokenId, uint256 postoneInSeconds) external {
        (address owner, uint256 releaseTime) = lockInfoOf(tokenId);
        require(msg.sender == owner, "require token owner");
        if (releaseTime < block.timestamp) {
            releaseTime = block.timestamp;
        }
        _lock(owner, tokenId, releaseTime + postoneInSeconds);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data) public virtual override returns (bytes4) {
        require(msg.sender == address(uniswapV3PositionsNFT), "only accept UniswapV3PositionsNFT");

        (, , address token0, address token1, uint256 fee, , , uint256 _liquidity, , , , ) = INonfungiblePosition(msg.sender).positions(tokenId);
        emit Deposit(from, tokenId, token0, token1, fee, _liquidity);

        uint256 lockInSeconds = 0;
        if (data.length > 0) lockInSeconds = abi.decode(data, (uint256));
        _lock(from, tokenId, block.timestamp + lockInSeconds);
        return this.onERC721Received.selector;
    }

    function _lock(address owner, uint256 tokenId, uint256 releaseTime) private {
        require(releaseTime <= type(uint96).max, "lock time overflow");
        _tokenData[tokenId] = (releaseTime << 160) | uint256(uint160(owner));
        emit TokenLocked(owner, tokenId, releaseTime);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function _collectFeesByTokenId(uint256 tokenId, address recipient) private returns (uint256 amount0, uint256 amount1) {
        INonfungiblePosition.CollectParams memory params = INonfungiblePosition.CollectParams({tokenId: tokenId, recipient: recipient, amount0Max: type(uint128).max, amount1Max: type(uint128).max});
        (amount0, amount1) = INonfungiblePosition(uniswapV3PositionsNFT).collect(params);
        emit CollectFees(msg.sender, recipient, tokenId, amount0, amount1);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function _collectFeesByTokenIdRefferal(uint256 tokenId, address recipient) private returns (uint256 amount0, uint256 amount1) {
        INonfungiblePosition.CollectParams memory params = INonfungiblePosition.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (amount0, amount1) = INonfungiblePosition(uniswapV3PositionsNFT).collect(params);

        (, , address token0, address token1, , , , , , , , ) = INonfungiblePosition(uniswapV3PositionsNFT).positions(tokenId);
        address[] memory payTokens = new address[](2);
        payTokens[0] = token0;
        payTokens[1] = token1;
        uint256[] memory values = new uint256[](2);
        values[0] = IERC20(token0).balanceOf(address(this));
        values[1] = IERC20(token1).balanceOf(address(this));

        transferOutTokenWithAncesors(collectionId, recipient, payTokens, values);
        emit CollectFees(msg.sender, recipient, tokenId, amount0, amount1);
    }
}
