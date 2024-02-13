// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IUnitagCallbackHandler.sol";
import "./interfaces/IERC1155SoulBond.sol";
import "./utils/StringUtils.sol";
import "./utils/OperatorGuard.sol";

contract UnitagMembershipCardV2 is ERC1155, Multicall, OperatorGuard, IUnitagCallbackHandler, IERC1155SoulBond {
    using Strings for uint256;

    mapping(uint256 => mapping(address => uint256)) private _boundBalances;

    string public name = "Unitag Membership Card";
    string public symbol = "UMC";

    constructor(address operator_) ERC1155("") {
        addOperator(operator_);
    }

    function boundOf(address account, uint256 id) public view returns (uint256 amount) {
        amount = _boundBalances[id][account];
    }

    function boundOfBatch(address[] memory accounts, uint256[] memory ids) public view returns (uint256[] memory amounts) {
        require(accounts.length == ids.length, "UnitagMembershipCard: accounts and ids length mismatch");
        amounts = new uint256[](accounts.length);
        for (uint256 index = 0; index < accounts.length; ++index) {
            amounts[index] = boundOf(accounts[index], ids[index]);
        }
    }

    function tokenBinded(address to, uint256 id, uint256 value, uint256 amount) external onlyOperator returns (uint256) {
        uint256 acc = value * amount;
        _boundBalances[id][to] += acc;
        emit BoundSingle(msg.sender, to, id, acc);
        return _boundBalances[id][to];
    }

    function tokenBindedBatch(address to, uint256 id, uint256[] calldata values, uint256[] calldata amounts) external onlyOperator returns (uint256) {
        require(values.length == amounts.length, "UnitagMembershipCard: values and amounts length mismatch");
        uint256 acc;
        for (uint256 index = 0; index < values.length; ++index) acc += values[index] * amounts[index];
        _boundBalances[id][to] += acc;
        emit BoundSingle(msg.sender, to, id, acc);
        return _boundBalances[id][to];
    }

    function setUri(string calldata uri_) external onlyOwner {
        _setURI(uri_);
    }

    function uri(uint256 id) public view virtual override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        return string(abi.encodePacked(ERC1155.uri(0), id.toString(), ".json"));
    }
}
