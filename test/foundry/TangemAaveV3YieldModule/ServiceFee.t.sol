// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { PRECISION } from "contracts/resources/Constants.sol";

contract ServiceFeeViewsTest is TangemAaveV3YieldModuleBase {
    uint internal constant INITIAL_OWNER_BALANCE = 200_000e6;

    function test_calculateServiceFee_AfterRevenue() public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        uint revenue = 10_000e6;

        _generateRevenue(address(yieldModule), revenue);

        uint expectedFee = revenue * SERVICE_FEE_RATE / PRECISION;
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), expectedFee);
    }

    // example of pre-seeding internal state through the harness
    function test_calculateServiceFee_IncludesPreseededFeeDebt() public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        uint feeDebt = 700e6;

        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt);

        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), feeDebt);
    }

    function testFuzz_calculateServiceFee(uint revenue, uint feeRate, uint feeDebt) public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        revenue = bound(revenue, 0, 1_000_000_000e6);
        feeRate = bound(feeRate, 0, PRECISION);
        feeDebt = bound(feeDebt, 0, 1_000_000e6);

        // the fee is computed with the rate stored at the latest fee payment
        yieldModule.exposed_setLatestFeePaymentState(
            address(yieldToken), INITIAL_OWNER_BALANCE, feeRate
        );
        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt);
        _generateRevenue(address(yieldModule), revenue);

        uint expectedFee = revenue * feeRate / PRECISION + feeDebt;
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), expectedFee);
    }

    function testFuzz_effectiveBalances(uint revenue, uint feeRate, uint feeDebt) public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        revenue = bound(revenue, 0, 1_000_000e6);
        feeRate = bound(feeRate, 0, PRECISION);
        // large debts make the fee exceed the protocol balance => clamping branch
        feeDebt = bound(feeDebt, 0, 2 * INITIAL_OWNER_BALANCE);

        yieldModule.exposed_setLatestFeePaymentState(
            address(yieldToken), INITIAL_OWNER_BALANCE, feeRate
        );
        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt);
        _generateRevenue(address(yieldModule), revenue);

        uint protocolBalance = INITIAL_OWNER_BALANCE + revenue;
        uint fee = yieldModule.calculateServiceFee(address(yieldToken));
        uint expectedEffective = protocolBalance > fee ? protocolBalance - fee : 0;

        assertEq(yieldModule.effectiveProtocolBalance(address(yieldToken)), expectedEffective);
        assertEq(
            yieldModule.effectiveBalance(address(yieldToken)),
            yieldToken.balanceOf(owner) + expectedEffective
        );
    }
}

contract FeeDebtRepaymentTest is TangemAaveV3YieldModuleBase {
    uint internal feeDebt = FEE_DEBT_SCENARIO_REVENUE * SERVICE_FEE_RATE / PRECISION;

    function testFuzz_enterProtocolByOwner_PartiallyRepaysFeeDebt(uint reEnterDeposit) public {
        reEnterDeposit = bound(reEnterDeposit, 1, feeDebt - 1);

        (TangemAaveV3YieldModuleHarness yieldModule,) =
            _createFeeDebtState(otherAccount, reEnterDeposit);

        // the whole deposit goes toward the debt (FeePaymentPartial path)
        assertEq(yieldModule.feeDebts(address(yieldToken)), feeDebt - reEnterDeposit);
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), feeDebt - reEnterDeposit);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), 0);
    }

    function testFuzz_enterProtocolByOwner_FullyRepaysFeeDebtWhenDepositCoversIt(
        uint reEnterDeposit
    ) public {
        reEnterDeposit = bound(reEnterDeposit, feeDebt, FEE_DEBT_SCENARIO_DEPOSIT);

        (TangemAaveV3YieldModuleHarness yieldModule,) =
            _createFeeDebtState(otherAccount, reEnterDeposit);

        assertEq(yieldModule.feeDebts(address(yieldToken)), 0);
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), 0);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), reEnterDeposit - feeDebt);
    }
}

contract FeeDebtAndEffectiveBalancesTest is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;
    uint internal remainingFeeDebt;

    function setUp() public override {
        super.setUp();
        (yieldModule, remainingFeeDebt) = _createFeeDebtState(otherAccount);
    }

    function test_calculateServiceFee_ReturnsPersistedDebtWhenProtocolBalanceIsNotAboveBaseline()
        public
        view
    {
        // partial fee payment during re-enter reduced the debt by the small deposit
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), remainingFeeDebt);
    }

    function test_effectiveProtocolBalance_ClampsToZeroWhenFeeExceedsProtocolBalance() public view {
        uint protocolBalance = yieldModule.protocolBalance(address(yieldToken));
        uint fee = yieldModule.calculateServiceFee(address(yieldToken));

        assertGt(fee, protocolBalance);
        assertEq(yieldModule.effectiveProtocolBalance(address(yieldToken)), 0);
    }

    function test_effectiveBalance_DoesNotUnderflowWhenFeeExceedsProtocolBalance() public view {
        uint ownerBalance = yieldToken.balanceOf(otherAccount);

        // protocol component is clamped to zero
        assertEq(yieldModule.effectiveBalance(address(yieldToken)), ownerBalance);
    }
}
