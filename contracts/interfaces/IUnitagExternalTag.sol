// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IUnitagExternalTag is IERC165 {
    event BalanceChanged(address indexed source, uint256 value);
    event BoundSingle(address indexed operator, address indexed source, uint256 id, uint256 value);

    function boundOf(address account) external view returns (uint256 amount);

    function balanceOf(address account) external view returns (uint256 amount);

    function mint(address to, uint256 amount, bool bindImmediately) external;
}
