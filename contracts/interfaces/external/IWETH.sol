// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint amount) external;
}
