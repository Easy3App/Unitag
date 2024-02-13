// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library UnitagLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes1 internal constant Separator = ":";

    function toArray(EnumerableSet.AddressSet storage addressSet) internal view returns (address[] memory content) {
        uint256 count = addressSet.length();
        content = new address[](count);
        for (uint256 index = 0; index < count; ++index) content[index] = address(uint160(uint256(addressSet._inner._values[index])));
    }

    function toArray(EnumerableSet.UintSet storage uintSet) internal view returns (uint256[] memory content) {
        uint256 count = uintSet.length();
        content = new uint256[](count);
        for (uint256 index = 0; index < count; ++index) content[index] = uint256(uintSet._inner._values[index]);
    }

    function composeTagFullName(string calldata collectionName, string calldata tagName) internal pure returns (string memory fullName) {
        fullName = string(abi.encodePacked(collectionName, Separator, tagName));
    }

    function collectionNameToId(string calldata collectionName) internal view returns (uint256 id) {
        id = uint256(keccak256(abi.encodePacked(block.chainid, collectionName, Separator)));
    }

    function tagNameToId(string calldata collectionName, string calldata tagName) internal view returns (uint256 id) {
        id = tagFullNameToId(composeTagFullName(collectionName, tagName));
    }

    function tagFullNameToId(string memory tagFullName) internal view returns (uint256 id) {
        id = uint256(keccak256(abi.encodePacked(block.chainid, tagFullName)));
    }

    function toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly {
            mstore(add(b, 32), x)
        }
    }

    function hashTokenId(
        string memory chainPrefix,
        address nftContract,
        uint256 tokenId
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(chainPrefix, nftContract, tokenId)));
    }
}
