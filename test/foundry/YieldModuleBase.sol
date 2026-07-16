// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BaseTest } from "test/foundry/BaseTest.sol";
import { YieldModuleGeneralHarness } from "test/foundry/harnesses/YieldModuleGeneralHarness.sol";
import { TestHelpers } from "test/foundry/utils/TestHelpers.sol";

import { SwapExecutionRegistry } from "contracts/core/SwapExecutionRegistry.sol";
import { TangemYieldModuleFactory } from "contracts/core/TangemYieldModuleFactory.sol";
import { TangemYieldProcessor } from "contracts/core/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { TangemERC2771Forwarder } from "contracts/metatx/TangemERC2771Forwarder.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { MerklDistributorMock } from "contracts/test/MerklDistributorMock.sol";
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

/// General yield-module test base: deploys shared infra (processor, factory, forwarder,
/// swap registry) and exposes general actor helpers that operate on `IYieldModule` + address.
/// Module-specific bases extend this and add pool/token-specific fixtures returning their
/// harness type.
abstract contract YieldModuleBase is BaseTest, TestHelpers {
    bytes32 internal constant FEE_PAYMENT_FAILED_EVENT_SIG =
        keccak256("FeePaymentFailed(address,uint256)");

    /* Common scenario amounts shared by the feature suites */
    uint internal constant INITIAL_OWNER_BALANCE = 400_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
    uint internal constant NETWORK_FEE = 1e6;
    uint internal constant NEW_FEE_RATE = 2_000;
    // service fee derived from ACCUMULATED_REVENUE at the default SERVICE_FEE_RATE
    uint internal constant ACCUMULATED_SERVICE_FEE =
        ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    // protocol balance after entering INITIAL_OWNER_BALANCE and generating ACCUMULATED_REVENUE
    uint internal constant PROTOCOL_BALANCE = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;

    uint internal constant FEE_DEBT_SCENARIO_DEPOSIT = 100_000e6;
    uint internal constant FEE_DEBT_SCENARIO_REVENUE = 10_000e6;

    TangemERC2771Forwarder public forwarder;
    TangemYieldProcessor public processor;
    TangemYieldModuleFactory public factory;
    SwapExecutionRegistry public swapExecutionRegistry;
    MerklDistributorMock public merklDistributor;
    SwapProviderMock public swapProvider;
    TestERC20 public yieldToken;
    YieldModuleGeneralHarness public ymGeneralImpl;

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
        merklDistributor = new MerklDistributorMock();
        swapProvider = new SwapProviderMock();
        yieldToken = new TestERC20("TestYieldToken", "TYT", 6);

        ymGeneralImpl = new YieldModuleGeneralHarness(
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry)
        );

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
        vm.label(address(merklDistributor), "merklDistributor");
        vm.label(address(swapProvider), "swapProvider");
        vm.label(address(yieldToken), "yieldToken");
        vm.label(address(ymGeneralImpl), "ymGeneralImpl");
    }

    /* GENERIC ACTOR HELPERS (operate via the processor on IYieldModule) */

    function _enterViaProcessor(
        IYieldModule yieldModule,
        address yieldTokenAddr,
        uint networkFee
    ) internal {
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _exitViaProcessor(
        IYieldModule yieldModule,
        address yieldTokenAddr,
        uint networkFee
    ) internal {
        vm.prank(backend);
        processor.exitProtocol(address(yieldModule), yieldTokenAddr, networkFee);
    }

    function _collectViaProcessor(IYieldModule yieldModule, address yieldTokenAddr) internal {
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule), yieldTokenAddr);
    }

    function _withdraw(
        IYieldModule yieldModule,
        address moduleOwner,
        address token,
        uint amount
    ) internal {
        vm.prank(moduleOwner);
        yieldModule.withdraw(token, amount);
    }

    function _withdrawAndDeactivate(
        IYieldModule yieldModule,
        address moduleOwner,
        address token
    ) internal {
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

    /* MINT HOOK (overridden by module-specific bases that need custom minting) */

    function _mintYieldToken(address to, uint amount) internal virtual {
        vm.prank(backend);
        yieldToken.mint(to, amount);
    }

    /* PROTOCOL HOOKS (overridden by module-specific bases) */

    /// Simulates protocol yield by minting protocol tokens to the account.
    /// Default: uses the general harness fake pool via the proxy. Override for AAVE/Morpho.
    function _generateRevenue(address yieldTokenAddr, address proxy, uint amount) internal virtual {
        // Mint yieldToken to the proxy so it can be returned on withdraw (revenue = extra yield).
        vm.prank(backend);
        TestERC20(yieldTokenAddr).mint(proxy, amount);
        // Mint protocolToken via the proxy to track _protocolBalance.
        YieldModuleGeneralHarness(payable(proxy)).generateRevenue(yieldTokenAddr, proxy, amount);
    }

    /* GENERIC FIXTURE HELPERS (operate on YieldModuleGeneralHarness) */

    /// Registers the general implementation in the factory and unpauses.
    /// Called by YieldModuleBase.setUp or by module-specific setUp if they use a different impl.
    function _registerGeneralImplementation() internal {
        vm.prank(backend);
        factory.setImplementation(address(ymGeneralImpl));
        vm.prank(backend);
        factory.unpause();
    }

    function _deployGeneralYieldModule(
        address moduleOwner,
        address yieldTokenAddr,
        uint240 maxNetworkFee
    ) internal returns (YieldModuleGeneralHarness yieldModule) {
        vm.prank(moduleOwner);
        factory.deployYieldModule(moduleOwner, yieldTokenAddr, maxNetworkFee);

        yieldModule =
            YieldModuleGeneralHarness(payable(factory.calculateYieldModuleAddress(moduleOwner)));
        vm.label(address(yieldModule), "yieldModule");
    }

    function _deployGeneralYieldModuleWithFunds(
        address moduleOwner,
        uint ownerBalance
    ) internal returns (YieldModuleGeneralHarness yieldModule) {
        yieldModule = _deployGeneralYieldModule(
            moduleOwner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE
        );

        _mintYieldToken(moduleOwner, ownerBalance);

        vm.prank(moduleOwner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    function _deployEnteredGeneralYieldModule(
        address moduleOwner,
        uint enterAmount
    ) internal returns (YieldModuleGeneralHarness yieldModule) {
        yieldModule = _deployGeneralYieldModuleWithFunds(moduleOwner, enterAmount);

        vm.prank(moduleOwner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    /// Full scenario: deployed, entered and revenue generated (standard ACCUMULATED_REVENUE).
    function _deployEnteredRevenueGeneralModule(address moduleOwner)
        internal
        returns (YieldModuleGeneralHarness yieldModule)
    {
        yieldModule = _deployGeneralYieldModuleWithFunds(moduleOwner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldToken), address(yieldModule), ACCUMULATED_REVENUE);
    }

    /* GENERIC HARNESS ACTOR WRAPPERS (bind yieldToken) */

    function _enterViaProcessor(YieldModuleGeneralHarness yieldModule, uint networkFee) internal {
        _enterViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _exitViaProcessor(YieldModuleGeneralHarness yieldModule, uint networkFee) internal {
        _exitViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _collectViaProcessor(YieldModuleGeneralHarness yieldModule) internal {
        _collectViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken));
    }

    /* FEE-DEBT SCENARIO (general, operates on YieldModuleGeneralHarness) */

    /// Scenario: fee debt persisted after failed fee payment, protocol balance below the debt.
    /// Returns the debt remaining after the partial payment (smallDeposit = 1e6).
    function _createGeneralFeeDebtState(address moduleOwner)
        internal
        returns (YieldModuleGeneralHarness yieldModule, uint remainingFeeDebt)
    {
        uint smallDeposit = 1e6;
        uint feeDebt;
        (yieldModule, feeDebt) = _createGeneralFeeDebtState(moduleOwner, smallDeposit);
        remainingFeeDebt = feeDebt - smallDeposit;
    }

    /// Same scenario with a configurable re-enter deposit (paid toward the debt).
    /// Returns the full debt as it was before the re-enter payment.
    function _createGeneralFeeDebtState(
        address moduleOwner,
        uint reEnterDeposit
    ) internal returns (YieldModuleGeneralHarness yieldModule, uint feeDebt) {
        feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

        yieldModule = _deployGeneralYieldModuleWithFunds(moduleOwner, FEE_DEBT_SCENARIO_DEPOSIT);

        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldToken), address(yieldModule), FEE_DEBT_SCENARIO_REVENUE);

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
}
