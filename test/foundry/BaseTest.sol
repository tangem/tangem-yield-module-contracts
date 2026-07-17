// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/src/Test.sol";

abstract contract BaseTest is Test {
    uint internal constant SERVICE_FEE_RATE = 100;
    uint internal constant POOL_LIQUIDITY = 1_000_000e6;
    uint internal constant AMOUNT = 1e18;
    uint internal constant YIELD_AMOUNT = 100e6;
    uint240 internal constant DEFAULT_MAX_NETWORK_FEE = 1e6;

    address public backend = makeAddr("backend");
    address public owner;
    uint public ownerPk;
    address public feeReceiver = makeAddr("feeReceiver");
    address public otherAccount = makeAddr("otherAccount");

    function setUp() public virtual {
        (owner, ownerPk) = makeAddrAndKey("owner");
    }
}
