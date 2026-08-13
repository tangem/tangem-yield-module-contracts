// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { YieldModuleFixture } from "test/foundry/YieldModuleFixture.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";

import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract AaveV3YieldModuleFixture is YieldModuleFixture {
    uint internal constant INITIAL_MODULE_BALANCE = 50_000e6;
    uint internal constant TOTAL_ENTER_AMOUNT = INITIAL_OWNER_BALANCE + INITIAL_MODULE_BALANCE;
    uint internal constant FRESH_OWNER_BALANCE = 50_000e6;

    TestERC20 public protocolToken;
    AaveV3PoolMock public pool;
    TangemAaveV3YieldModuleHarness public implementation;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(backend);

        pool = new AaveV3PoolMock();
        yieldToken.mint(address(pool), POOL_LIQUIDITY);

        implementation = new TangemAaveV3YieldModuleHarness(
            address(pool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry),
            address(wrappedNative)
        );

        factory.setImplementation(address(implementation));
        factory.unpause();

        vm.stopPrank();

        protocolToken = pool.aToken();

        _labelAaveAddresses();
    }

    function _labelAaveAddresses() internal {
        vm.label(address(protocolToken), "protocolToken");
        vm.label(address(pool), "aavePoolMock");
        vm.label(address(implementation), "implementation");
    }

    /* AAVE-SPECIFIC HELPERS */

    /// Simulates protocol yield by minting protocol (aave) tokens to the account.
    function _generateRevenue(address account, uint amount) internal {
        pool.generateRevenue(account, amount);
    }

    function _generateRevenue(address, address account, uint amount) internal override {
        pool.generateRevenue(account, amount);
    }
}
