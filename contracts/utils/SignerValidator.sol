// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract SignerValidator {
    address public remoteSigner;

    constructor(address remoteSigner_) {
        _setRemoteSigner(remoteSigner_);
    }

    function _setRemoteSigner(address remoteSigner_) internal {
        remoteSigner = remoteSigner_;
    }

    function _validSignature(bytes32 msgHash, bytes memory signature) internal view {
        address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(msgHash), signature);
        require(signer == remoteSigner, "invalid signature");
    }
}
