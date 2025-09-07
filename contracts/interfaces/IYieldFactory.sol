// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;


interface IYieldFactory {
    
    function isValidImplementation(address implementation_) external view returns (bool);
}