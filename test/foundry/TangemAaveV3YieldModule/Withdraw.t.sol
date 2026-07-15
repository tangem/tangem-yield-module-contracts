// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { Requires } from "contracts/common/Requires.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract WithdrawTest is TangemAaveV3YieldModuleBase {
    uint internal constant WITHDRAW_AMOUNT = 2_000e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModuleWithFunds(owner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);

        serviceFee = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    }

    function test_withdraw_WithdrawsSpecifiedAmountFromPoolToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(address(yieldToken), WITHDRAW_AMOUNT, owner);

        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), WITHDRAW_AMOUNT);
    }

    function test_withdraw_ProcessesServiceFeeAndEmitsWithdrawProcessed() public {
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawProcessed(address(yieldToken), WITHDRAW_AMOUNT);

        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), WITHDRAW_AMOUNT);
    }

    function test_withdraw_UpdatesLatestFeePaymentState() public {
        uint newFeeRate = 700;
        _setServiceFeeRate(newFeeRate);

        uint expectedProtocolBalance = PROTOCOL_BALANCE - WITHDRAW_AMOUNT - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, INITIAL_OWNER_BALANCE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), WITHDRAW_AMOUNT);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, newFeeRate);
    }

    // any amount up to protocolBalance - fee succeeds; the fee is always reserved
    function testFuzz_withdraw(uint amount) public {
        amount = bound(amount, 1, PROTOCOL_BALANCE - serviceFee);

        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), amount);

        assertEq(yieldToken.balanceOf(owner), amount);
        assertEq(protocolToken.balanceOf(feeReceiver), serviceFee);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE - amount - serviceFee);
    }

    function testFuzz_withdraw_RevertsInsufficientFundsWhenAmountPlusFeeExceedsProtocolBalance(uint amount) public {
        amount = bound(amount, PROTOCOL_BALANCE - serviceFee + 1, type(uint128).max);

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), amount);
    }

    function test_withdraw_RevertsTokenNotActive() public {
        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), 1e6);
    }

    function test_withdraw_RevertsZeroAmount() public {
        vm.expectRevert(Requires.ZeroAmount.selector);
        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), 0);
    }

    function test_withdraw_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.withdraw(address(yieldToken), 1e6);
    }

    function test_withdraw_SyncsLatestFeePaymentStateWithoutFeeWhenFeeIsZero() public {
        uint deposit = 5_000e6;
        uint amount = 1_000e6;

        TangemAaveV3YieldModuleHarness yieldModule2 = _deployYieldModuleWithFunds(otherAccount, deposit);
        // no revenue => service fee is zero
        _enterViaProcessor(yieldModule2, 0);

        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.LatestFeePaymentStateUpdated(address(yieldToken), deposit - amount, SERVICE_FEE_RATE);
        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), 0, feeReceiver);

        vm.recordLogs();
        vm.prank(otherAccount);
        yieldModule2.withdraw(address(yieldToken), amount);

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }
}
