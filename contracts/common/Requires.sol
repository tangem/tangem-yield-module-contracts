// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
