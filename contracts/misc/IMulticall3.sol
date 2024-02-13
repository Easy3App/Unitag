// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 

contract ZkFairStake  {

    struct DepositInfo {
        address depositor;
        uint256 amount;
        uint256 duration; // Duration in days
        uint256 timestamp;
        uint256 nonce;
    }
 
    mapping(address => DepositInfo[9]) public deposits; 
}