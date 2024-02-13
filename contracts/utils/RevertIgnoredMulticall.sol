// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Multicall.sol";

abstract contract RevertIgnoredMulticall is Multicall {
    event MulticallReverts(string reason);

    /**
     * @dev Receives and executes a batch of function calls on this contract and ignore execution reverts.
     */
    function multicallIgnoreReverts(bytes[] calldata data) external {
        for (uint256 index = 0; index < data.length; ++index) {
            functionDelegateCallIgnoreReverts(data[index]);
        }
    }
 
    function functionDelegateCallIgnoreReverts(bytes memory data) internal {
        (bool success, bytes memory returndata) = address(this).delegatecall(data);
        if (!success) {
            if (returndata.length > 0) {
                emit MulticallReverts(string(returndata));
            } else {
                emit MulticallReverts("low-level delegate call failed");
            }
        }
    }
}
