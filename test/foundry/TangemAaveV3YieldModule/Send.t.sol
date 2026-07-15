// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract SendTest is TangemAaveV3YieldModuleBase {
    uint internal constant INITIAL_OWNER_BALANCE = 400_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
    uint internal constant PROTOCOL_BALANCE = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;
    uint internal constant FRESH_OWNER_BALANCE = 5_000e6;
    uint internal constant SEND_AMOUNT = 25_000e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    address internal receiver;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        receiver = otherAccount;

        yieldModule = _deployYieldModuleWithFunds(owner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);

        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);

        serviceFee = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;
    }

    function _send(uint amount) internal {
        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, amount);
    }

    function test_send_WithdrawsMissingAmountFromPoolToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(address(yieldToken), SEND_AMOUNT - FRESH_OWNER_BALANCE, owner);

        _send(SEND_AMOUNT);
    }

    function test_send_DoesNotWithdrawWhenOwnerBalanceCoversAmount() public {
        _mintYieldToken(owner, SEND_AMOUNT);

        vm.recordLogs();
        _send(SEND_AMOUNT);

        _assertEventNotEmitted(vm.getRecordedLogs(), POOL_WITHDRAW_EVENT_SIG);
    }

    function test_send_TransfersAmountFromOwnerToReceiver() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, receiver, SEND_AMOUNT);

        _send(SEND_AMOUNT);
    }

    function test_send_RevertsSendingToOwner() public {
        vm.expectRevert(IYieldModule.SendingToOwner.selector);
        vm.prank(owner);
        yieldModule.send(address(yieldToken), owner, SEND_AMOUNT);
    }

    function test_send_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.send(address(yieldToken), receiver, SEND_AMOUNT);
    }

    function test_send_EmitsSendProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SendProcessed(address(yieldToken), receiver, SEND_AMOUNT);

        _send(SEND_AMOUNT);
    }

    /* Fee processing */

    function test_send_SetsLatestFeePaymentState() public {
        uint newFeeRate = 300;
        _setServiceFeeRate(newFeeRate);

        uint expectedProtocolBalance =
            PROTOCOL_BALANCE - SEND_AMOUNT - serviceFee + FRESH_OWNER_BALANCE;

        (uint protocolBalance, uint serviceFeeRate) =
            yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, INITIAL_OWNER_BALANCE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _send(SEND_AMOUNT);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, newFeeRate);
    }

    function test_send_TransfersServiceFeeToFeeReceiver() public {
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);

        _send(SEND_AMOUNT);
    }

    function test_send_DoesNotProcessFeeWhenOwnerBalanceCoversAmount() public {
        _mintYieldToken(owner, SEND_AMOUNT);

        vm.recordLogs();
        _send(SEND_AMOUNT);
        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_PROCESSED_EVENT_SIG);

        _mintYieldToken(owner, SEND_AMOUNT);

        vm.recordLogs();
        _send(SEND_AMOUNT);
        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }

    function test_send_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        _send(SEND_AMOUNT);
    }

    function test_send_RevertsInsufficientFundsWhenPullAmountExceedsProtocolBalanceMinusFee()
        public
    {
        uint protocolBalance = yieldModule.protocolBalance(address(yieldToken));
        uint fee = yieldModule.calculateServiceFee(address(yieldToken));

        // pullAmount = protocolBalance - fee + 1 => must fail due to fee reservation
        uint sendAmount = FRESH_OWNER_BALANCE + protocolBalance - fee + 1;

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, sendAmount);
    }
}
