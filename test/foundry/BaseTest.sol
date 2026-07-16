// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";

abstract contract BaseTest is Test {
    uint internal constant SERVICE_FEE_RATE = 100;
    uint240 internal constant DEFAULT_MAX_NETWORK_FEE = 10e6;

    address public backend = makeAddr("backend");
    address public owner = makeAddr("owner");
    address public feeReceiver = makeAddr("feeReceiver");
    address public otherAccount = makeAddr("otherAccount");
}