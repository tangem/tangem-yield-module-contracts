// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "./AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

/// Non-standard ERC20 behavior at the module boundaries.
contract WeirdTokensTest is AaveV3YieldModuleBase {
    uint internal constant WITHDRAW_AMOUNT = 2_000e6;
    uint internal constant SEND_AMOUNT = 25_000e6;
    uint internal constant TAX = 1e6;
    uint internal constant BALANCE_DROP = 20_000e6;
    uint internal constant FOT_DEPOSIT = 100_000e6;

    YieldModuleHarness internal yieldModule;
    address internal receiver;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployEnteredRevenueModule(owner);
        serviceFee = ACCUMULATED_SERVICE_FEE;
        receiver = otherAccount;
    }

    /*  fee transfer failure (protocol-token leg)  */

    function test_withdraw_SucceedsAndRecordsFeeDebtWhenFeeTransferToReceiverFails() public {
        protocolToken.blacklist(feeReceiver);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentFailed(address(yieldToken), serviceFee);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawProcessed(address(yieldToken), WITHDRAW_AMOUNT);

        _withdraw(yieldModule, owner, address(yieldToken), WITHDRAW_AMOUNT);

        assertEq(yieldToken.balanceOf(owner), WITHDRAW_AMOUNT);
        assertEq(protocolToken.balanceOf(feeReceiver), 0);
        assertEq(yieldModule.feeDebts(address(yieldToken)), serviceFee);

        (uint checkpoint,) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpoint, PROTOCOL_BALANCE - WITHDRAW_AMOUNT);
    }

    /*  fee-on-transfer token  */

    function test_enterProtocolByOwner_SuppliesPostTaxBalanceWhenYieldTokenHasTransferTax() public {
        address fotOwner = makeAddr("fotOwner");
        YieldModuleHarness fotModule =
            _deployYieldModuleWithFunds(fotOwner, FOT_DEPOSIT);

        yieldToken.setFixedTax(TAX);

        vm.prank(fotOwner);
        fotModule.enterProtocolByOwner(address(yieldToken));

        assertEq(fotModule.protocolBalance(address(yieldToken)), FOT_DEPOSIT - TAX);
        assertEq(yieldToken.balanceOf(address(fotModule)), 0);

        (uint checkpoint,) = fotModule.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpoint, FOT_DEPOSIT - TAX);
    }

    function test_send_TransfersAmountMinusTaxWhenOwnerBalanceCoversAmount() public {
        _mintYieldToken(owner, SEND_AMOUNT);
        yieldToken.setFixedTax(TAX);

        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, SEND_AMOUNT);

        assertEq(yieldToken.balanceOf(receiver), SEND_AMOUNT - TAX);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    function test_send_Reverts_WhenTaxErodesAmountPulledFromProtocol() public {
        yieldToken.setFixedTax(TAX);

        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        vm.prank(owner);
        yieldModule.send(address(yieldToken), receiver, SEND_AMOUNT);
    }

    /*  negative rebase / balance slashing  */

    function test_withdrawAndDeactivate_ChargesNoFeeWhenProtocolBalanceDropsBelowCheckpoint()
        public
    {
        // simulate a negative rebase: burn the revenue plus part of the principal
        protocolToken.forceBurn(address(yieldModule), ACCUMULATED_REVENUE + BALANCE_DROP);
        uint remaining = INITIAL_OWNER_BALANCE - BALANCE_DROP;

        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), 0);

        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        assertEq(yieldToken.balanceOf(owner), remaining);
        assertEq(protocolToken.balanceOf(feeReceiver), 0);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), 0);

        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }
}
