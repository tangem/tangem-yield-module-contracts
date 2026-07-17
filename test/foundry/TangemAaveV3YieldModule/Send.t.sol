// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "./AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract SendTest is AaveV3YieldModuleBase {
    uint internal constant SEND_FRESH_OWNER_BALANCE = 5_000e6;
    uint internal constant SEND_AMOUNT = 25_000e6;

    YieldModuleHarness internal yieldModule;
    address internal receiver;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        receiver = otherAccount;

        yieldModule = _deployYieldModuleWithFunds(owner, INITIAL_OWNER_BALANCE);
        _enterViaProcessor(yieldModule, 0);

        _mintYieldToken(owner, SEND_FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);

        serviceFee = ACCUMULATED_SERVICE_FEE;
    }

    function _send(uint amount) internal {
        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, amount);
    }

    function test_send_WithdrawsMissingAmountFromPoolToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(
            address(yieldToken),
            SEND_AMOUNT - SEND_FRESH_OWNER_BALANCE,
            owner
        );

        _send(SEND_AMOUNT);
    }

    function test_send_DoesNotWithdrawWhenOwnerBalanceCoversAmount() public {
        _mintYieldToken(owner, SEND_AMOUNT);

        vm.recordLogs();
        _send(SEND_AMOUNT);

        _assertEventNotEmitted(vm.getRecordedLogs(), keccak256("Withdraw(address,uint256,address)"));
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

    function test_send_RevertsTokenNotActive() public {
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        _send(SEND_AMOUNT);
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
            PROTOCOL_BALANCE - SEND_AMOUNT - serviceFee + SEND_FRESH_OWNER_BALANCE;

        _assertLatestFeePaymentState(yieldModule, INITIAL_OWNER_BALANCE, SERVICE_FEE_RATE);

        _send(SEND_AMOUNT);

        _assertLatestFeePaymentState(yieldModule, expectedProtocolBalance, newFeeRate);
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
        _assertEventNotEmitted(
            vm.getRecordedLogs(), keccak256("FeePaymentProcessed(address,uint256,address)")
        );

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

    // owner balance covers the amount first; only the missing part is pulled (with fee reserved)
    function testFuzz_send(uint amount) public {
        amount = bound(amount, 1, SEND_FRESH_OWNER_BALANCE + PROTOCOL_BALANCE - serviceFee);
        uint pullAmount = amount > SEND_FRESH_OWNER_BALANCE ? amount - SEND_FRESH_OWNER_BALANCE : 0;

        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, amount);

        assertEq(yieldToken.balanceOf(receiver), amount, "receiver");

        if (pullAmount > 0) {
            assertEq(
                yieldModule.protocolBalance(address(yieldToken)),
                PROTOCOL_BALANCE - pullAmount - serviceFee,
                "protocol"
            );
            assertEq(protocolToken.balanceOf(feeReceiver), serviceFee, "fee");
        } else {
            // protocol untouched => no fee processed
            assertEq(yieldModule.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE, "protocol");
            assertEq(protocolToken.balanceOf(feeReceiver), 0, "fee");
        }
    }

    function testFuzz_send_RevertsInsufficientFundsWhenPullAmountExceedsProtocolBalanceMinusFee(uint amount)
        public
    {
        uint maxAmount = SEND_FRESH_OWNER_BALANCE + PROTOCOL_BALANCE - serviceFee;
        amount = bound(amount, maxAmount + 1, type(uint128).max);

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, amount);
    }
}
