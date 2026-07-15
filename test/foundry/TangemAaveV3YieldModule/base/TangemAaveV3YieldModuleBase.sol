// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Vm } from "forge-std/src/Test.sol";

import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemBaseTest } from "test/foundry/helpers/TangemBaseTest.sol";

import { SwapExecutionRegistry } from "contracts/core/SwapExecutionRegistry.sol";
import { TangemYieldModuleFactory } from "contracts/core/TangemYieldModuleFactory.sol";
import { TangemYieldProcessor } from "contracts/core/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { TangemERC2771Forwarder } from "contracts/metatx/TangemERC2771Forwarder.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";
import { MerklDistributorMock } from "contracts/test/MerklDistributorMock.sol";
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract TangemAaveV3YieldModuleBase is TangemBaseTest {
    bytes32 internal constant POOL_WITHDRAW_EVENT_SIG =
        keccak256("Withdraw(address,uint256,address)");
    bytes32 internal constant FEE_PAYMENT_PROCESSED_EVENT_SIG =
        keccak256("FeePaymentProcessed(address,uint256,address)");
    bytes32 internal constant FEE_PAYMENT_FAILED_EVENT_SIG =
        keccak256("FeePaymentFailed(address,uint256)");

    uint internal constant FEE_DEBT_SCENARIO_DEPOSIT = 100_000e6;
    uint internal constant FEE_DEBT_SCENARIO_REVENUE = 10_000e6;

    TestERC20 public yieldToken;
    TestERC20 public protocolToken;
    TangemERC2771Forwarder public forwarder;
    AaveV3PoolMock public pool;
    TangemYieldProcessor public processor;
    TangemYieldModuleFactory public factory;
    SwapExecutionRegistry public swapExecutionRegistry;
    MerklDistributorMock public merklDistributor;
    SwapProviderMock public swapProvider;
    TangemAaveV3YieldModuleHarness public implementation;

    function setUp() public virtual {
        vm.startPrank(backend);

        yieldToken = new TestERC20();
        forwarder = new TangemERC2771Forwarder();
        pool = new AaveV3PoolMock();
        yieldToken.mint(address(pool), POOL_LIQUIDITY);

        processor = new TangemYieldProcessor(feeReceiver, SERVICE_FEE_RATE);
        processor.grantRole(processor.PROTOCOL_ENTERER_ROLE(), backend);
        processor.grantRole(processor.PROTOCOL_EXITER_ROLE(), backend);
        processor.grantRole(processor.SERVICE_FEE_COLLECTOR_ROLE(), backend);
        processor.grantRole(processor.PROPERTY_SETTER_ROLE(), backend);
        processor.grantRole(processor.PAUSER_ROLE(), backend);

        factory = new TangemYieldModuleFactory();
        swapExecutionRegistry = new SwapExecutionRegistry(backend);
        merklDistributor = new MerklDistributorMock();
        swapProvider = new SwapProviderMock();

        implementation = new TangemAaveV3YieldModuleHarness(
            address(pool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry)
        );

        factory.grantRole(factory.IMPLEMENTATION_SETTER_ROLE(), backend);
        factory.grantRole(factory.PAUSER_ROLE(), backend);
        factory.setImplementation(address(implementation));
        factory.unpause();

        vm.stopPrank();

        protocolToken = pool.aToken();

        _labelAddresses();
    }

    /* FIXTURE HELPERS */

    function _deployYieldModule(
        address moduleOwner,
        address yieldTokenAddr,
        uint240 maxNetworkFee
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule) {
        vm.prank(moduleOwner);
        factory.deployYieldModule(moduleOwner, yieldTokenAddr, maxNetworkFee);

        yieldModule = TangemAaveV3YieldModuleHarness(
            payable(factory.calculateYieldModuleAddress(moduleOwner))
        );
        vm.label(address(yieldModule), "yieldModule");
    }

    /// Deploys a module with the yield token initialized, owner funded and max approval given.
    function _deployYieldModuleWithFunds(
        address moduleOwner,
        uint ownerBalance
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModule(moduleOwner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(moduleOwner, ownerBalance);

        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    /// Full scenario: deployed module with funds already supplied to the protocol.
    function _deployEnteredYieldModule(
        address moduleOwner,
        uint enterAmount
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule) {
        yieldModule = _deployYieldModuleWithFunds(moduleOwner, enterAmount);

        vm.prank(moduleOwner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    /// Scenario: fee debt persisted after failed fee payment, protocol balance below the debt.
    /// Mirrors the hardhat "Fee debt persistence" setup: enter, generate revenue, force fee
    /// failure on exit, then reactivate and re-enter with a small deposit (paid toward the debt).
    /// Returns the debt remaining after that partial payment.
    function _createFeeDebtState(address moduleOwner)
        internal
        returns (TangemAaveV3YieldModuleHarness yieldModule, uint remainingFeeDebt)
    {
        uint smallDeposit = 1e6;
        uint feeDebt;
        (yieldModule, feeDebt) = _createFeeDebtState(moduleOwner, smallDeposit);
        remainingFeeDebt = feeDebt - smallDeposit;
    }

    /// Same scenario with a configurable re-enter deposit (paid toward the debt).
    /// Returns the full debt as it was before the re-enter payment.
    function _createFeeDebtState(
        address moduleOwner,
        uint reEnterDeposit
    ) internal returns (TangemAaveV3YieldModuleHarness yieldModule, uint feeDebt) {
        feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

        yieldModule = _deployYieldModule(moduleOwner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
        _mintYieldToken(moduleOwner, FEE_DEBT_SCENARIO_DEPOSIT);
        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);

        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), FEE_DEBT_SCENARIO_REVENUE);

        // revoke allowance so the exit fee payment (owner transferFrom path) fails => debt persists
        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), 0);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentFailed(address(yieldToken), feeDebt);
        _exitViaProcessor(yieldModule, 0);

        // remove withdrawn funds so the re-enter below controls the protocol balance exactly
        uint ownerBalanceAfterExit = yieldToken.balanceOf(moduleOwner);
        vm.prank(moduleOwner);
        yieldToken.transfer(backend, ownerBalanceAfterExit);

        vm.prank(moduleOwner);
        yieldModule.reactivateToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(moduleOwner, reEnterDeposit);
        vm.startPrank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
        yieldModule.enterProtocolByOwner(address(yieldToken));
        vm.stopPrank();
    }

    function _enterViaProcessor(
        TangemAaveV3YieldModuleHarness yieldModule,
        uint networkFee
    ) internal {
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), address(yieldToken), networkFee);
    }

    function _exitViaProcessor(
        TangemAaveV3YieldModuleHarness yieldModule,
        uint networkFee
    ) internal {
        vm.prank(backend);
        processor.exitProtocol(address(yieldModule), address(yieldToken), networkFee);
    }

    function _collectViaProcessor(TangemAaveV3YieldModuleHarness yieldModule) internal {
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule), address(yieldToken));
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

    function _deployTestToken() internal returns (TestERC20 token) {
        vm.prank(backend);
        token = new TestERC20();
    }

    function _mintYieldToken(address to, uint amount) internal {
        vm.prank(backend);
        yieldToken.mint(to, amount);
    }

    function _mintToken(TestERC20 token, address to, uint amount) internal {
        vm.prank(backend);
        token.mint(to, amount);
    }

    /// Simulates protocol yield by minting protocol (aave) tokens to the account.
    function _generateRevenue(address account, uint amount) internal {
        pool.generateRevenue(account, amount);
    }

    function _assertEventNotEmitted(Vm.Log[] memory entries, bytes32 eventSig) internal pure {
        for (uint i; i < entries.length; i++) {
            require(entries[i].topics[0] != eventSig, "expected event not to be emitted");
        }
    }

    function _labelAddresses() internal {
        vm.label(address(yieldToken), "yieldToken");
        vm.label(address(protocolToken), "protocolToken");
        vm.label(address(pool), "aavePoolMock");
        vm.label(address(processor), "processor");
        vm.label(address(factory), "factory");
        vm.label(address(swapExecutionRegistry), "swapExecutionRegistry");
        vm.label(address(merklDistributor), "merklDistributor");
        vm.label(address(swapProvider), "swapProvider");
        vm.label(address(forwarder), "forwarder");
        vm.label(address(implementation), "implementation");
    }
}
