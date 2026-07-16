// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BaseTest } from "test/foundry/BaseTest.sol";
import { TestHelpers } from "test/foundry/utils/TestHelpers.sol";

import { SwapExecutionRegistry } from "contracts/core/SwapExecutionRegistry.sol";
import { TangemYieldModuleFactory } from "contracts/core/TangemYieldModuleFactory.sol";
import { TangemYieldProcessor } from "contracts/core/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { TangemERC2771Forwarder } from "contracts/metatx/TangemERC2771Forwarder.sol";

/// Generic yield-module test base: deploys shared infra (processor, factory, forwarder,
/// swap registry) and exposes generic actor helpers that operate on `IYieldModule` + address.
/// Module-specific bases extend this and add pool/token-specific fixtures returning their
/// harness type.
abstract contract YieldModuleBase is BaseTest, TestHelpers {
    bytes32 internal constant FEE_PAYMENT_PROCESSED_EVENT_SIG =
        keccak256("FeePaymentProcessed(address,uint256,address)");
    bytes32 internal constant FEE_PAYMENT_FAILED_EVENT_SIG =
        keccak256("FeePaymentFailed(address,uint256)");

    /* Common scenario amounts shared by the feature suites */
    uint internal constant INITIAL_OWNER_BALANCE = 400_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
    uint internal constant NETWORK_FEE = 1e6;
    uint internal constant NEW_FEE_RATE = 2_000;

    TangemERC2771Forwarder public forwarder;
    TangemYieldProcessor public processor;
    TangemYieldModuleFactory public factory;
    SwapExecutionRegistry public swapExecutionRegistry;

    function setUp() public virtual {
        vm.startPrank(backend);

        forwarder = new TangemERC2771Forwarder();

        processor = new TangemYieldProcessor(feeReceiver, SERVICE_FEE_RATE);
        processor.grantRole(processor.PROTOCOL_ENTERER_ROLE(), backend);
        processor.grantRole(processor.PROTOCOL_EXITER_ROLE(), backend);
        processor.grantRole(processor.SERVICE_FEE_COLLECTOR_ROLE(), backend);
        processor.grantRole(processor.PROPERTY_SETTER_ROLE(), backend);
        processor.grantRole(processor.PAUSER_ROLE(), backend);

        factory = new TangemYieldModuleFactory();
        swapExecutionRegistry = new SwapExecutionRegistry(backend);

        factory.grantRole(factory.IMPLEMENTATION_SETTER_ROLE(), backend);
        factory.grantRole(factory.PAUSER_ROLE(), backend);

        vm.stopPrank();

        _labelAddresses();
    }

    function _labelAddresses() internal virtual {
        vm.label(address(processor), "processor");
        vm.label(address(factory), "factory");
        vm.label(address(swapExecutionRegistry), "swapExecutionRegistry");
        vm.label(address(forwarder), "forwarder");
    }

    /* GENERIC ACTOR HELPERS (operate via the processor on IYieldModule) */

    function _enterViaProcessor(IYieldModule yieldModule, address yieldTokenAddr, uint networkFee)
        internal
    {
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _exitViaProcessor(IYieldModule yieldModule, address yieldTokenAddr, uint networkFee)
        internal
    {
        vm.prank(backend);
        processor.exitProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _collectViaProcessor(IYieldModule yieldModule, address yieldTokenAddr) internal {
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule), yieldTokenAddr);
    }

    function _withdraw(IYieldModule yieldModule, address moduleOwner, address token, uint amount)
        internal
    {
        vm.prank(moduleOwner);
        yieldModule.withdraw(token, amount);
    }

    function _withdrawAndDeactivate(IYieldModule yieldModule, address moduleOwner, address token)
        internal
    {
        vm.prank(moduleOwner);
        yieldModule.withdrawAndDeactivate(token);
    }

    function _setServiceFeeRate(uint feeRate) internal {
        vm.prank(backend);
        processor.setServiceFeeRate(feeRate);
    }

    function _allowSwapProvider(address provider) internal {
        vm.startPrank(backend);
        swapExecutionRegistry.setTargetAllowed(provider, true);
        swapExecutionRegistry.setSpenderAllowed(provider, true);
        vm.stopPrank();
    }

    /* MINT HOOK (overridden by module-specific bases for their token type) */

    function _mintYieldToken(address to, uint amount) internal virtual {
        // no-op: overridden by module-specific base
    }
}