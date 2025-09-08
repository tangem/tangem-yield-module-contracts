// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Requires {
    error ZeroAmount();
    error ZeroAddress();
  
    function requireNotZero(uint amount) internal pure {
        require(amount > 0, ZeroAmount());
    }
    
    function requireNotZero(address address_) internal pure {
        require(address_ != address(0), ZeroAddress());
    }
}