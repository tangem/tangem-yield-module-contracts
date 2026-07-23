// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { YieldModuleBase } from "../YieldModuleBase.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { PRECISION } from "contracts/resources/Constants.sol";

contract ServiceFeeTest is YieldModuleBase {
    uint internal constant SF_INITIAL_OWNER_BALANCE = 200_000e6;
    uint internal feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

    YieldModuleHarness internal debtModule;
    uint internal remainingFeeDebt;
    address internal debtOwner = makeAddr("debtOwner");

    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();
        (debtModule, remainingFeeDebt) = _createFeeDebtState(debtOwner);
    }

    /*  calculateServiceFee  */

    function test_calculateServiceFee_AfterRevenue() public {
        YieldModuleHarness yieldModule = _deployEnteredYieldModule(owner, SF_INITIAL_OWNER_BALANCE);
        uint revenue = 10_000e6;

        _generateRevenue(address(yieldToken), address(yieldModule), revenue);

        uint expectedFee = revenue * SERVICE_FEE_RATE / PRECISION;
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), expectedFee);
    }

    // example of pre-seeding internal state through the harness
    function test_calculateServiceFee_IncludesPreseededFeeDebt() public {
        YieldModuleHarness yieldModule = _deployEnteredYieldModule(owner, SF_INITIAL_OWNER_BALANCE);
        uint feeDebt_ = 700e6;

        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt_);

        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), feeDebt_);
    }

    function testFuzz_calculateServiceFee(uint revenue, uint feeRate, uint feeDebt_) public {
        YieldModuleHarness yieldModule = _deployEnteredYieldModule(owner, SF_INITIAL_OWNER_BALANCE);
        revenue = bound(revenue, 0, 1_000_000_000e6);
        feeRate = bound(feeRate, 0, PRECISION);
        feeDebt_ = bound(feeDebt_, 0, 1_000_000e6);

        // the fee is computed with the rate stored at the latest fee payment
        yieldModule.exposed_setLatestFeePaymentState(address(yieldToken), SF_INITIAL_OWNER_BALANCE, feeRate);
        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt_);
        _generateRevenue(address(yieldToken), address(yieldModule), revenue);

        uint expectedFee = revenue * feeRate / PRECISION + feeDebt_;
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), expectedFee);
    }

    function testFuzz_effectiveBalances(uint revenue, uint feeRate, uint feeDebt_) public {
        YieldModuleHarness yieldModule = _deployEnteredYieldModule(owner, SF_INITIAL_OWNER_BALANCE);
        revenue = bound(revenue, 0, 1_000_000e6);
        feeRate = bound(feeRate, 0, PRECISION);
        // large debts make the fee exceed the protocol balance => clamping branch
        feeDebt_ = bound(feeDebt_, 0, 2 * SF_INITIAL_OWNER_BALANCE);

        yieldModule.exposed_setLatestFeePaymentState(address(yieldToken), SF_INITIAL_OWNER_BALANCE, feeRate);
        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt_);
        _generateRevenue(address(yieldToken), address(yieldModule), revenue);

        uint protocolBalance = SF_INITIAL_OWNER_BALANCE + revenue;
        uint fee = yieldModule.calculateServiceFee(address(yieldToken));
        uint expectedEffective = protocolBalance > fee ? protocolBalance - fee : 0;

        assertEq(yieldModule.effectiveProtocolBalance(address(yieldToken)), expectedEffective);
        assertEq(yieldModule.effectiveBalance(address(yieldToken)), yieldToken.balanceOf(owner) + expectedEffective);
    }

    /*  Fee debt repayment  */

    function testFuzz_enterProtocolByOwner_PartiallyRepaysFeeDebt(uint reEnterDeposit) public {
        reEnterDeposit = bound(reEnterDeposit, 1, feeDebt - 1);

        (YieldModuleHarness yieldModule,) = _createFeeDebtState(otherAccount, reEnterDeposit);

        // the whole deposit goes toward the debt (FeePaymentPartial path)
        assertEq(yieldModule.feeDebts(address(yieldToken)), feeDebt - reEnterDeposit);
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), feeDebt - reEnterDeposit);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), 0);
    }

    function testFuzz_enterProtocolByOwner_FullyRepaysFeeDebtWhenDepositCoversIt(uint reEnterDeposit) public {
        reEnterDeposit = bound(reEnterDeposit, feeDebt, FEE_DEBT_SCENARIO_DEPOSIT);

        (YieldModuleHarness yieldModule,) = _createFeeDebtState(otherAccount, reEnterDeposit);

        assertEq(yieldModule.feeDebts(address(yieldToken)), 0);
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), 0);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), reEnterDeposit - feeDebt);
    }

    /*  Fee debt & effective balances  */

    function test_calculateServiceFee_ReturnsPersistedDebtWhenProtocolBalanceIsNotAboveBaseline() public view {
        // partial fee payment during re-enter reduced the debt by the small deposit
        assertEq(debtModule.calculateServiceFee(address(yieldToken)), remainingFeeDebt);
    }

    function test_effectiveProtocolBalance_ClampsToZeroWhenFeeExceedsProtocolBalance() public view {
        uint protocolBalance = debtModule.protocolBalance(address(yieldToken));
        uint fee = debtModule.calculateServiceFee(address(yieldToken));

        assertGt(fee, protocolBalance);
        assertEq(debtModule.effectiveProtocolBalance(address(yieldToken)), 0);
    }

    function test_effectiveBalance_DoesNotUnderflowWhenFeeExceedsProtocolBalance() public view {
        uint ownerBalance = yieldToken.balanceOf(debtOwner);

        // protocol component is clamped to zero
        assertEq(debtModule.effectiveBalance(address(yieldToken)), ownerBalance);
    }
}
