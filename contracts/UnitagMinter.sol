// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUnitag.sol";
import "./utils/SignerValidator.sol";

contract UnitagMinter is SignerValidator, Ownable {
    event Mint(address indexed operator, address indexed to, uint256 tagId, uint256 amount, bool bindImmediately);
    event MintBatch(address indexed operator, address indexed to, uint256[] tagIds, uint256[] amounts, bool bindImmediately);

    address public unitag;

    bytes32 private _payloadPrefix;

    // account => nonce
    mapping(address => uint256) public nonces;

    constructor(address signer_, address unitag_) SignerValidator(signer_) {
        setUnitag(unitag_);
    }

    function setUnitag(address unitag_) public onlyOwner {
        unitag = unitag_;
        _payloadPrefix = keccak256(abi.encode(block.chainid, unitag_, address(this)));
    }

    function setSigner(address signer_) external onlyOwner {
        _setRemoteSigner(signer_);
    }

    function mint(
        address to,
        uint256 tagId,
        uint256 amount,
        bool bindImmediately,
        bytes calldata signature
    ) external {
        uint256 _nonce = _updateWithdrawalNonce(to);
        bytes32 payload = keccak256(abi.encode(_payloadPrefix, to, tagId, amount, bindImmediately, _nonce));
        _validSignature(payload, signature);
        IUnitag(unitag).mint(to, tagId, amount, bindImmediately);
        emit Mint(msg.sender, to, tagId, amount, bindImmediately);
    }

    function mintBatch(
        address to,
        uint256[] calldata tagIds,
        uint256[] calldata amounts,
        bool bindImmediately,
        bytes calldata signature
    ) external {
        uint256 _nonce = _updateWithdrawalNonce(to);
        bytes32 payload = keccak256(abi.encode(_payloadPrefix, to, tagIds, amounts, bindImmediately, _nonce));
        _validSignature(payload, signature);
        IUnitag(unitag).mintBatch(to, tagIds, amounts, bindImmediately);
        emit MintBatch(msg.sender, to, tagIds, amounts, bindImmediately);
    } 

    /**
     * @dev update withdraw nonce
     */
    function _updateWithdrawalNonce(address account) private returns (uint256) {
        uint256 nonce = nonces[account];
        nonces[account] = nonce + 1;
        return nonce;
    }
}
