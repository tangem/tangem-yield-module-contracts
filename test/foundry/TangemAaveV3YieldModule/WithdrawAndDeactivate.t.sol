// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract WithdrawAndDeactivateTest is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModuleWithFunds(owner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);

        serviceFee = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    }

    function test_withdrawAndDeactivate_WithdrawsProtocolBalanceMinusFeeToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(address(yieldToken), PROTOCOL_BALANCE - serviceFee, owner);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    function test_withdrawAndDeactivate_DeactivatesYieldToken() public {
        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(active);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        (, active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }

    function test_withdrawAndDeactivate_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    function test_withdrawAndDeactivate_EmitsWithdrawAndDeactivateProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawAndDeactivateProcessed(address(yieldToken), PROTOCOL_BALANCE - serviceFee);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    /* Fee processing */

    function test_withdrawAndDeactivate_SetsLatestFeePaymentState() public {
        uint newFeeRate = 300;
        _setServiceFeeRate(newFeeRate);

        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, INITIAL_OWNER_BALANCE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, newFeeRate);
    }

    function test_withdrawAndDeactivate_TransfersServiceFeeToFeeReceiver() public {
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    function test_withdrawAndDeactivate_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    function test_withdrawAndDeactivate_SyncsLatestFeePaymentStateWithoutFeeWhenFeeIsZero() public {
        uint deposit = 5_000e6;

        TangemAaveV3YieldModuleHarness yieldModule2 = _deployYieldModuleWithFunds(otherAccount, deposit);
        // first enter, no revenue => baseline set, fee == 0
        _enterViaProcessor(yieldModule2, 0);

        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.LatestFeePaymentStateUpdated(address(yieldToken), 0, SERVICE_FEE_RATE);
        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), 0, feeReceiver);

        vm.recordLogs();
        vm.prank(otherAccount);
        yieldModule2.withdrawAndDeactivate(address(yieldToken));

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }

    function test_withdrawAndDeactivate_SucceedsWhenPersistedFeeDebtExceedsProtocolBalance() public {
        (TangemAaveV3YieldModuleHarness yieldModule2, uint remainingFeeDebt) = _createFeeDebtState(otherAccount);

        // partial fee payment during re-enter reduced the debt by the small deposit
        assertEq(yieldModule2.feeDebts(address(yieldToken)), remainingFeeDebt);

        vm.prank(otherAccount);
        yieldModule2.withdrawAndDeactivate(address(yieldToken));

        (, bool active,) = yieldModule2.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }
}
