// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/src/Test.sol";

abstract contract TangemBaseTest is Test {
    // service fee rate in basis points (PRECISION = 10000)
    uint internal constant SERVICE_FEE_RATE = 100;
    uint internal constant POOL_LIQUIDITY = 1_000_000e6;
    // realistic gas compensation cap in token units (~10 USDC)
    uint240 internal constant DEFAULT_MAX_NETWORK_FEE = 10e6;

    address public backend = makeAddr("backend");
    address public owner = makeAddr("owner");
    address public feeReceiver = makeAddr("feeReceiver");
    address public otherAccount = makeAddr("otherAccount");

    function _assertEventNotEmitted(Vm.Log[] memory entries, bytes32 eventSig) internal pure {
        for (uint i; i < entries.length; i++) {
            require(entries[i].topics[0] != eventSig, "expected event not to be emitted");
        }
    }
}
