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
    uint internal constant INITIAL_OWNER_BALANCE = 100_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
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

        uint expectedProtocolBalance =
            INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE - WITHDRAW_AMOUNT - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) =
            yieldModule.latestFeePaymentStates(address(yieldToken));
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
        uint protocolBalance = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;
        amount = bound(amount, 1, protocolBalance - serviceFee);

        vm.prank(owner);
        yieldModule.withdraw(address(yieldToken), amount);

        assertEq(yieldToken.balanceOf(owner), amount);
        assertEq(protocolToken.balanceOf(feeReceiver), serviceFee);
        assertEq(
            yieldModule.protocolBalance(address(yieldToken)),
            protocolBalance - amount - serviceFee
        );
    }

    function testFuzz_withdraw_RevertsInsufficientFundsWhenAmountPlusFeeExceedsProtocolBalance(
        uint amount
    ) public {
        uint protocolBalance = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;
        amount = bound(amount, protocolBalance - serviceFee + 1, type(uint128).max);

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

        TangemAaveV3YieldModuleHarness yieldModule2 =
            _deployYieldModuleWithFunds(otherAccount, deposit);
        // no revenue => service fee is zero
        _enterViaProcessor(yieldModule2, 0);

        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.LatestFeePaymentStateUpdated(
            address(yieldToken),
            deposit - amount,
            SERVICE_FEE_RATE
        );
        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), 0, feeReceiver);

        vm.recordLogs();
        vm.prank(otherAccount);
        yieldModule2.withdraw(address(yieldToken), amount);

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }
}

contract WithdrawAndDeactivateTest is TangemAaveV3YieldModuleBase {
    uint internal constant INITIAL_OWNER_BALANCE = 400_000e6;
    uint internal constant ACCUMULATED_REVENUE = 10_000e6;
    uint internal constant PROTOCOL_BALANCE = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE;

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
        emit IYieldModule.WithdrawAndDeactivateProcessed(
            address(yieldToken),
            PROTOCOL_BALANCE - serviceFee
        );

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

    /* Fee processing */

    function test_withdrawAndDeactivate_SetsLatestFeePaymentState() public {
        uint newFeeRate = 300;
        _setServiceFeeRate(newFeeRate);

        (uint protocolBalance, uint serviceFeeRate) =
            yieldModule.latestFeePaymentStates(address(yieldToken));
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

        TangemAaveV3YieldModuleHarness yieldModule2 =
            _deployYieldModuleWithFunds(otherAccount, deposit);
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

    function test_withdrawAndDeactivate_SucceedsWhenPersistedFeeDebtExceedsProtocolBalance()
        public
    {
        (TangemAaveV3YieldModuleHarness yieldModule2, uint remainingFeeDebt) =
            _createFeeDebtState(otherAccount);

        // partial fee payment during re-enter reduced the debt by the small deposit
        assertEq(yieldModule2.feeDebts(address(yieldToken)), remainingFeeDebt);

        vm.prank(otherAccount);
        yieldModule2.withdrawAndDeactivate(address(yieldToken));

        (, bool active,) = yieldModule2.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }
}

contract WithdrawNonYieldTokenTest is TangemAaveV3YieldModuleBase {
    uint internal constant MODULE_BALANCE = 4_000_000e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    address internal nonYieldToken;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModule(owner, address(0), 0);
        _mintYieldToken(address(yieldModule), MODULE_BALANCE);

        nonYieldToken = address(yieldToken);
    }

    function test_withdrawNonYieldToken_TransfersTotalModuleBalanceToOwner() public {
        vm.expectEmit(nonYieldToken);
        emit IERC20.Transfer(address(yieldModule), owner, MODULE_BALANCE);

        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }

    function test_withdrawNonYieldToken_RevertsWithdrawingYieldToken() public {
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(IYieldModule.WithdrawingYieldToken.selector);
        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(address(yieldToken));
    }

    function test_withdrawNonYieldToken_RevertsWithdrawingProtocolToken() public {
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(IYieldModule.WithdrawingProtocolToken.selector);
        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(address(protocolToken));
    }

    function test_withdrawNonYieldToken_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }

    function test_withdrawNonYieldToken_EmitsWithdrawNonYieldProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawNonYieldProcessed(nonYieldToken, MODULE_BALANCE);

        vm.prank(owner);
        yieldModule.withdrawNonYieldToken(nonYieldToken);
    }
}

contract WithdrawNativeAllTest is TangemAaveV3YieldModuleBase {
    uint internal constant NATIVE_BALANCE = 0.001 ether;

    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_withdrawNativeAll_EmitsWithdrawNativeProcessedWithZeroAmountWhenBalanceIsZero()
        public
    {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawNativeProcessed(backend, 0);

        vm.prank(owner);
        yieldModule.withdrawNativeAll(backend);
    }

    function test_withdrawNativeAll_TransfersNativeBalanceAndEmitsWithdrawNativeProcessed() public {
        vm.deal(address(yieldModule), NATIVE_BALANCE);
        uint receiverBalanceBefore = backend.balance;

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawNativeProcessed(backend, NATIVE_BALANCE);

        vm.prank(owner);
        yieldModule.withdrawNativeAll(backend);

        assertEq(address(yieldModule).balance, 0);
        assertEq(backend.balance, receiverBalanceBefore + NATIVE_BALANCE);
    }

    function test_withdrawNativeAll_RevertsNativeTransferFailed() public {
        vm.deal(address(yieldModule), NATIVE_BALANCE);
        // contract without receive/fallback
        address badReceiver = address(swapExecutionRegistry);

        vm.expectRevert(IYieldModule.NativeTransferFailed.selector);
        vm.prank(owner);
        yieldModule.withdrawNativeAll(badReceiver);
    }

    function test_withdrawNativeAll_RevertsZeroAddress() public {
        vm.expectRevert(Requires.ZeroAddress.selector);
        vm.prank(owner);
        yieldModule.withdrawNativeAll(address(0));
    }

    function test_withdrawNativeAll_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.withdrawNativeAll(backend);
    }
}
