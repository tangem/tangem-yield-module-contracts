// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TangemBaseTest } from "test/foundry/helpers/TangemBaseTest.sol";

import { SwapExecutionRegistry } from "contracts/core/SwapExecutionRegistry.sol";

abstract contract SwapExecutionRegistryBase is TangemBaseTest {
    SwapExecutionRegistry public registry;

    function setUp() public virtual {
        vm.prank(backend);
        registry = new SwapExecutionRegistry(backend);
        vm.label(address(registry), "swapExecutionRegistry");
    }
}
