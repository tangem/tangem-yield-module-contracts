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
