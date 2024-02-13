// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "../utils/SignerValidator.sol"; 

contract TicketConsumer is SignerValidator, Ownable {
    event TicketConsumed(uint256 indexed id, address indexed operator, uint256 amount);

    mapping(uint256 => mapping(address => uint256)) public consumerNonce;

    constructor(address signer_) SignerValidator(signer_) {}

    function consumeTicket(uint256 id, uint256 amount, bytes calldata signature) external {
        uint256 nonce = _updateConsumerNonce(id, msg.sender);
        bytes32 payload = keccak256(abi.encode(block.chainid, address(this), id, msg.sender, amount, nonce));
        _validSignature(payload, signature);
        emit TicketConsumed(id, msg.sender, amount);
    }

    function setSigner(address signer_) external onlyOwner {
        _setRemoteSigner(signer_);
    }

    /**
     * @dev update withdraw nonce
     */
    function _updateConsumerNonce(uint256 id, address account) private returns (uint256) {
        uint256 nonce = consumerNonce[id][account];
        consumerNonce[id][account] = nonce + 1;
        return nonce;
    }
}
