// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;


interface IYieldProcessor {
    
    function feeReceiver() external view returns (address);

    // rate is specified in basis points (0.01 %)
    function serviceFeeRate() external returns (uint);
}