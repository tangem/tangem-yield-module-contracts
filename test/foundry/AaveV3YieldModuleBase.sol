// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";
import { YieldModuleBase } from "test/foundry/YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract AaveV3YieldModuleBase is YieldModuleBase {
    /* Aave scenario amounts */
    uint internal constant INITIAL_MODULE_BALANCE = 50_000e6;
    uint internal constant TOTAL_ENTER_AMOUNT = INITIAL_OWNER_BALANCE + INITIAL_MODULE_BALANCE;
    // service fee derived from ACCUMULATED_REVENUE at the default SERVICE_FEE_RATE
    uint internal constant ACCUMULATED_SERVICE_FEE = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    // protocol balance after entering INITIAL_OWNER_BALANCE and generating ACCUMULATED_REVENUE
    uint internal constant PROTOCOL_BALANCE = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;
    uint internal constant FRESH_OWNER_BALANCE = 50_000e6;

    uint internal constant FEE_DEBT_SCENARIO_DEPOSIT = 100_000e6;
    uint internal constant FEE_DEBT_SCENARIO_REVENUE = 10_000e6;

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
            address(swapExecutionRegistry)
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

    /* FIXTURE HELPERS (return the Aave harness type) */

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

    /// Full scenario: deployed, entered and revenue generated (standard ACCUMULATED_REVENUE).
    function _deployEnteredRevenueModule(address moduleOwner)
        internal
        returns (TangemAaveV3YieldModuleHarness yieldModule)
    {
        yieldModule = _deployYieldModuleWithFunds(moduleOwner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
    }

    /* AAVE-SPECIFIC ACTOR WRAPPERS (bind yieldToken) */

    function _enterViaProcessor(TangemAaveV3YieldModuleHarness yieldModule, uint networkFee)
        internal
    {
        _enterViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _exitViaProcessor(TangemAaveV3YieldModuleHarness yieldModule, uint networkFee)
        internal
    {
        _exitViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken), networkFee);
    }

    function _collectViaProcessor(TangemAaveV3YieldModuleHarness yieldModule) internal {
        _collectViaProcessor(IYieldModule(address(yieldModule)), address(yieldToken));
    }

    /* FEE-DEBT SCENARIO */

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

        yieldModule = _deployYieldModuleWithFunds(moduleOwner, FEE_DEBT_SCENARIO_DEPOSIT);

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

    /* AAVE-SPECIFIC HELPERS */

    /// Simulates protocol yield by minting protocol (aave) tokens to the account.
    function _generateRevenue(address account, uint amount) internal {
        pool.generateRevenue(account, amount);
    }
}