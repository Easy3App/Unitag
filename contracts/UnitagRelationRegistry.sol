// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUnitagRelationRegistry.sol";
import "./utils/SignerValidator.sol";

contract UnitagRelationRegistry is IUnitagRelationRegistry, SignerValidator, Ownable {
    event SetParent(uint256 indexed collectionId, address account, address parent);
    // collection id => address => parent
    mapping(uint256 => mapping(uint256 => uint256)) private _ancestorRegistry;

    constructor(address signer_) SignerValidator(signer_) {}

    /**
     * @dev Set signer
     */
    function setSigner(address signer_) external onlyOwner {
        _setRemoteSigner(signer_);
    }

    /**
     * @param collectionId the id of the collection
     * @param accounts  the accounts to set
     * @param signature the signatures of the accounts
     */
    function setParent(uint256 collectionId, address[] calldata accounts, bytes calldata signature) external {
        bytes32 payload = keccak256(abi.encode(collectionId, accounts));
        _validSignature(payload, signature);
        // convert account to uint256 by add 1 < 160
        uint256 base = _composeAddress(accounts[0]);
        uint256 accountLength = accounts.length;
        for (uint256 index = 1; index < accountLength; ++index) {
            uint256 parentBase = _composeAddress(accounts[index]);
            // get old parent
            uint256 oldParent = _ancestorRegistry[collectionId][base];
            // if old parent is not 0, means it has parent before.
            if (oldParent == 0) {
                // set new parent
                _ancestorRegistry[collectionId][base] = parentBase;
                emit SetParent(collectionId, address(uint160(base)), address(uint160(parentBase)));
            }
            base = parentBase;
        }
    }

    /**
     * @dev check if the account account has ancestor
     * @param collectionId the id of the collection
     * @param account the account to query
     */
    function hasAncestor(uint256 collectionId, address account) external view returns (bool) {
        return _ancestorRegistry[collectionId][_composeAddress(account)] != 0;
    }

    /**
     * @dev Get direct ancestor of one account(parent)
     * @param collectionId the id of the collection
     * @param account the account to query
     */
    function ancestor(uint256 collectionId, address account) external view returns (address) {
        return address(uint160(_ancestorRegistry[collectionId][_composeAddress(account)]));
    }

    /**
     * @dev Get multi level ancestor of one account
     * @param collectionId the id of the collection
     * @param account the account to query
     * @param level the levels to query
     */
    function ancestors(uint256 collectionId, address account, uint256 level) external view returns (address[] memory _ancestors) {
        _ancestors = new address[](level);
        uint256 base = _composeAddress(account);
        uint256 count;
        for (uint256 index = 0; index < level; ++index) {
            base = _ancestorRegistry[collectionId][base];
            address parent = address(uint160(base));
            if (parent == address(0)) break;
            _ancestors[count] = parent;
            ++count;
        }
        assembly {
            mstore(_ancestors, count)
        }
    }

    /**
     * @dev Compose address to uint256 by add 1 < 160
     * @param input the address to convert
     */
    function _composeAddress(address input) private pure returns (uint256 output) {
        output = uint256(uint160(input)) | (1 << 160);
    }
}
