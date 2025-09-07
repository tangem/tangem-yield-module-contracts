// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Requires {
  
    function requireNotZero(uint amount) internal pure {
        require(amount > 0, "Common: amount is zero");
    }
    
    function requireNotZero(address address_) internal pure {
        require(address_ != address(0), "Common: address is zero");
    }
}