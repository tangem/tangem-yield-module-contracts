// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract EnterProtocolByOwnerTest is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(owner, INITIAL_OWNER_BALANCE);
        _mintYieldToken(address(yieldModule), INITIAL_MODULE_BALANCE);

        vm.prank(owner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    function _enter() internal {
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    /// enter all, accumulate revenue, mint fresh funds, change the fee rate
    function _setupConsecutiveEnter() internal returns (uint serviceFee) {
        serviceFee = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;

        _enter();
        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
        _setServiceFeeRate(NEW_FEE_RATE);
    }

    function test_enterProtocolByOwner_TransfersAllOwnerFundsToModule() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, address(yieldModule), INITIAL_OWNER_BALANCE);

        _enter();
    }

    function test_enterProtocolByOwner_ApprovesTotalAmountToPool() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Approval(address(yieldModule), address(pool), TOTAL_ENTER_AMOUNT);

        _enter();
    }

    function test_enterProtocolByOwner_SuppliesPoolOnBehalfOfModule() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(yieldToken), TOTAL_ENTER_AMOUNT, address(yieldModule), 0);

        _enter();
    }

    function test_enterProtocolByOwner_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    function test_enterProtocolByOwner_EmitsProtocolEntered() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.ProtocolEntered(address(yieldToken), TOTAL_ENTER_AMOUNT, 0);

        _enter();
    }

    /* Fee processing: first enter */

    function test_enterProtocolByOwner_FirstEnter_SetsLatestFeePaymentState() public {
        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, 0);

        _enter();

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);
    }

    function test_enterProtocolByOwner_FirstEnter_EmitsFeePaymentProcessedWithZeroFee() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.LatestFeePaymentStateUpdated(address(yieldToken), TOTAL_ENTER_AMOUNT, SERVICE_FEE_RATE);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), 0, feeReceiver);

        vm.recordLogs();
        _enter();

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }

    /* Fee processing: consecutive enters */

    function test_enterProtocolByOwner_ConsecutiveEnter_UpdatesLatestFeePaymentState() public {
        uint serviceFee = _setupConsecutiveEnter();
        uint expectedProtocolBalance = TOTAL_ENTER_AMOUNT + ACCUMULATED_REVENUE + FRESH_OWNER_BALANCE - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _enter();

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, NEW_FEE_RATE);
    }

    function test_enterProtocolByOwner_ConsecutiveEnter_TransfersServiceFeeToFeeReceiver() public {
        uint serviceFee = _setupConsecutiveEnter();

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);

        _enter();
    }

    function test_enterProtocolByOwner_ConsecutiveEnter_EmitsFeePaymentProcessed() public {
        uint serviceFee = _setupConsecutiveEnter();

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        _enter();
    }
}
