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

contract EnterProtocolTest is TangemAaveV3YieldModuleBase {
    uint internal constant ENTER_AMOUNT = 150_000e6;
    uint internal constant SECOND_ENTER_AMOUNT = 100_000e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    TangemAaveV3YieldModuleHarness internal amountModule;
    address internal amountOwner = makeAddr("amountOwner");

    function setUp() public override {
        super.setUp();

        // Main module: owner funds + module pre-balance (enterProtocol & enterProtocolByOwner full)
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(owner, INITIAL_OWNER_BALANCE);
        _mintYieldToken(address(yieldModule), INITIAL_MODULE_BALANCE);

        vm.prank(owner);
        yieldToken.approve(address(yieldModule), type(uint).max);

        // Amount module: owner funds only, no module pre-balance (enterProtocolByOwner with amount)
        amountModule = _deployYieldModuleWithFunds(amountOwner, INITIAL_OWNER_BALANCE);
    }

    /* ================================================ enterProtocol (processor) ================================================ */

    function test_enterProtocol_TransfersAllOwnerFundsToModule() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, address(yieldModule), INITIAL_OWNER_BALANCE);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_enterProtocol_ApprovesTotalAmountToPool() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Approval(address(yieldModule), address(pool), TOTAL_ENTER_AMOUNT);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_enterProtocol_SuppliesPoolOnBehalfOfModule() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(yieldToken), TOTAL_ENTER_AMOUNT, address(yieldModule), 0);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    function testFuzz_enterProtocol_AnyNetworkFeeUpToMax(uint networkFee) public {
        networkFee = bound(networkFee, 0, DEFAULT_MAX_NETWORK_FEE);

        _enterViaProcessor(yieldModule, networkFee);

        assertEq(yieldModule.protocolBalance(address(yieldToken)), TOTAL_ENTER_AMOUNT - networkFee);
        assertEq(protocolToken.balanceOf(feeReceiver), networkFee);

        (uint protocolBalance,) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT - networkFee);
    }

    function testFuzz_enterProtocol_RevertsNetworkFeeExceedsMax(uint networkFee) public {
        networkFee = bound(networkFee, uint(DEFAULT_MAX_NETWORK_FEE) + 1, type(uint128).max);

        vm.expectRevert(IYieldModule.NetworkFeeExceedsMax.selector);
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), address(yieldToken), networkFee);
    }

    function test_enterProtocol_RevertsNetworkFeeExceedsAmount() public {
        _enterViaProcessor(yieldModule, NETWORK_FEE);
        _mintYieldToken(owner, NETWORK_FEE);

        vm.expectRevert(IYieldModule.NetworkFeeExceedsAmount.selector);
        vm.prank(backend);
        processor.enterProtocol(address(yieldModule), address(yieldToken), NETWORK_FEE);
    }

    function test_enterProtocol_RevertsOnlyProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        vm.prank(owner);
        yieldModule.enterProtocol(address(yieldToken), NETWORK_FEE);
    }

    function test_enterProtocol_EmitsProtocolEntered() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.ProtocolEntered(address(yieldToken), TOTAL_ENTER_AMOUNT, NETWORK_FEE);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    /* Fee processing: first enter */

    function test_enterProtocol_FirstEnter_SetsLatestFeePaymentState() public {
        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, 0);

        _enterViaProcessor(yieldModule, NETWORK_FEE);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT - NETWORK_FEE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);
    }

    function test_enterProtocol_FirstEnter_TransfersNetworkFeeToFeeReceiver() public {
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, NETWORK_FEE);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_enterProtocol_FirstEnter_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), NETWORK_FEE, feeReceiver);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    /* Fee processing: consecutive enters */

    /// first enter without a network fee, then accumulate revenue and change the fee rate
    function _setupConsecutiveEnter() internal returns (uint serviceFee) {
        serviceFee = ACCUMULATED_SERVICE_FEE;

        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));

        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
        _setServiceFeeRate(NEW_FEE_RATE);
    }

    function test_enterProtocol_ConsecutiveEnter_UpdatesLatestFeePaymentState() public {
        uint serviceFee = _setupConsecutiveEnter();
        uint expectedProtocolBalance =
            TOTAL_ENTER_AMOUNT + ACCUMULATED_REVENUE + FRESH_OWNER_BALANCE - serviceFee - NETWORK_FEE;

        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _enterViaProcessor(yieldModule, NETWORK_FEE);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, NEW_FEE_RATE);
    }

    function test_enterProtocol_ConsecutiveEnter_TransfersServiceAndNetworkFeeToFeeReceiver() public {
        uint serviceFee = _setupConsecutiveEnter();

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee + NETWORK_FEE);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_enterProtocol_ConsecutiveEnter_EmitsFeePaymentProcessed() public {
        uint serviceFee = _setupConsecutiveEnter();

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee + NETWORK_FEE, feeReceiver);

        _enterViaProcessor(yieldModule, NETWORK_FEE);
    }

    // fee is computed with the rate stored at the previous payment; the new rate is stored for later
    function testFuzz_enterProtocol_ConsecutiveEnter(uint revenue, uint newFeeRate) public {
        revenue = bound(revenue, 0, 1_000_000e6);
        newFeeRate = bound(newFeeRate, 0, PRECISION);

        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));

        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), revenue);
        _setServiceFeeRate(newFeeRate);

        uint serviceFee = revenue * SERVICE_FEE_RATE / PRECISION;

        _enterViaProcessor(yieldModule, NETWORK_FEE);

        (uint protocolBalance, uint storedFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT + revenue + FRESH_OWNER_BALANCE - serviceFee - NETWORK_FEE);
        assertEq(storedFeeRate, newFeeRate);
        assertEq(protocolToken.balanceOf(feeReceiver), serviceFee + NETWORK_FEE);
    }

    /* ============================================ enterProtocolByOwner (full balance) =========================================== */

    function _enterByOwner() internal {
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    function test_enterProtocolByOwner_TransfersAllOwnerFundsToModule() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, address(yieldModule), INITIAL_OWNER_BALANCE);

        _enterByOwner();
    }

    function test_enterProtocolByOwner_ApprovesTotalAmountToPool() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Approval(address(yieldModule), address(pool), TOTAL_ENTER_AMOUNT);

        _enterByOwner();
    }

    function test_enterProtocolByOwner_SuppliesPoolOnBehalfOfModule() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(yieldToken), TOTAL_ENTER_AMOUNT, address(yieldModule), 0);

        _enterByOwner();
    }

    function test_enterProtocolByOwner_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    function test_enterProtocolByOwner_EmitsProtocolEntered() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.ProtocolEntered(address(yieldToken), TOTAL_ENTER_AMOUNT, 0);

        _enterByOwner();
    }

    /* Fee processing: first enter */

    function test_enterProtocolByOwner_FirstEnter_SetsLatestFeePaymentState() public {
        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, 0);

        _enterByOwner();

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
        _enterByOwner();

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }

    /* Fee processing: consecutive enters */

    /// enter all, accumulate revenue, mint fresh funds, change the fee rate
    function _setupConsecutiveEnterByOwner() internal returns (uint serviceFee) {
        serviceFee = ACCUMULATED_SERVICE_FEE;

        _enterByOwner();
        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
        _setServiceFeeRate(NEW_FEE_RATE);
    }

    function test_enterProtocolByOwner_ConsecutiveEnter_UpdatesLatestFeePaymentState() public {
        uint serviceFee = _setupConsecutiveEnterByOwner();
        uint expectedProtocolBalance = TOTAL_ENTER_AMOUNT + ACCUMULATED_REVENUE + FRESH_OWNER_BALANCE - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, TOTAL_ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _enterByOwner();

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, NEW_FEE_RATE);
    }

    function test_enterProtocolByOwner_ConsecutiveEnter_TransfersServiceFeeToFeeReceiver() public {
        uint serviceFee = _setupConsecutiveEnterByOwner();

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);

        _enterByOwner();
    }

    function test_enterProtocolByOwner_ConsecutiveEnter_EmitsFeePaymentProcessed() public {
        uint serviceFee = _setupConsecutiveEnterByOwner();

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        _enterByOwner();
    }

    /* ============================================ enterProtocolByOwner (with amount) =========================================== */

    function _enterByOwnerAmount(uint amount) internal {
        vm.prank(amountOwner);
        amountModule.enterProtocolByOwner(address(yieldToken), amount);
    }

    function _setupConsecutiveEnterByOwnerAmount() internal returns (uint serviceFee) {
        serviceFee = ACCUMULATED_SERVICE_FEE;

        _enterByOwnerAmount(ENTER_AMOUNT);
        _mintYieldToken(amountOwner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(amountModule), ACCUMULATED_REVENUE);
        _setServiceFeeRate(NEW_FEE_RATE);
    }

    function test_enterProtocolByOwnerAmount_TransfersOnlySpecifiedAmount() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(amountOwner, address(amountModule), ENTER_AMOUNT);

        _enterByOwnerAmount(ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_SuppliesPoolWithSpecifiedAmountOnly() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(yieldToken), ENTER_AMOUNT, address(amountModule), 0);

        _enterByOwnerAmount(ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_LeavesRemainingBalanceOnOwner() public {
        _enterByOwnerAmount(ENTER_AMOUNT);

        assertEq(yieldToken.balanceOf(amountOwner), INITIAL_OWNER_BALANCE - ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_EmitsProtocolEntered() public {
        vm.expectEmit(address(amountModule));
        emit IYieldModule.ProtocolEntered(address(yieldToken), ENTER_AMOUNT, 0);

        _enterByOwnerAmount(ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(owner);
        amountModule.enterProtocolByOwner(address(yieldToken), ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_RevertsZeroAmount() public {
        vm.expectRevert(Requires.ZeroAmount.selector);
        vm.prank(amountOwner);
        amountModule.enterProtocolByOwner(address(yieldToken), 0);
    }

    function test_enterProtocolByOwnerAmount_RevertsTokenNotActive() public {
        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        vm.prank(amountOwner);
        amountModule.enterProtocolByOwner(address(0), ENTER_AMOUNT);
    }

    function testFuzz_enterProtocolByOwnerAmount(uint amount) public {
        amount = bound(amount, 1, INITIAL_OWNER_BALANCE);

        _enterByOwnerAmount(amount);

        assertEq(amountModule.protocolBalance(address(yieldToken)), amount);
        assertEq(yieldToken.balanceOf(amountOwner), INITIAL_OWNER_BALANCE - amount);
    }

    /* Fee processing: first enter */

    function test_enterProtocolByOwnerAmount_FirstEnter_SetsLatestFeePaymentState() public {
        (uint protocolBalance, uint serviceFeeRate) = amountModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, 0);

        _enterByOwnerAmount(ENTER_AMOUNT);

        (protocolBalance, serviceFeeRate) = amountModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);
    }

    function test_enterProtocolByOwnerAmount_FirstEnter_EmitsFeePaymentProcessedWithZeroFee() public {
        vm.expectEmit(address(amountModule));
        emit IYieldModule.LatestFeePaymentStateUpdated(address(yieldToken), ENTER_AMOUNT, SERVICE_FEE_RATE);
        vm.expectEmit(address(amountModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), 0, feeReceiver);

        vm.recordLogs();
        _enterByOwnerAmount(ENTER_AMOUNT);

        _assertEventNotEmitted(vm.getRecordedLogs(), FEE_PAYMENT_FAILED_EVENT_SIG);
    }

    /* Fee processing: consecutive enters */

    function test_enterProtocolByOwnerAmount_ConsecutiveEnter_UpdatesLatestFeePaymentState() public {
        uint serviceFee = _setupConsecutiveEnterByOwnerAmount();
        uint expectedProtocolBalance = ENTER_AMOUNT + ACCUMULATED_REVENUE + SECOND_ENTER_AMOUNT - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) = amountModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, ENTER_AMOUNT);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _enterByOwnerAmount(SECOND_ENTER_AMOUNT);

        (protocolBalance, serviceFeeRate) = amountModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, NEW_FEE_RATE);
    }

    function test_enterProtocolByOwnerAmount_ConsecutiveEnter_TransfersServiceFeeToFeeReceiver() public {
        uint serviceFee = _setupConsecutiveEnterByOwnerAmount();

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(amountModule), feeReceiver, serviceFee);

        _enterByOwnerAmount(SECOND_ENTER_AMOUNT);
    }

    function test_enterProtocolByOwnerAmount_ConsecutiveEnter_EmitsFeePaymentProcessed() public {
        uint serviceFee = _setupConsecutiveEnterByOwnerAmount();

        vm.expectEmit(address(amountModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        _enterByOwnerAmount(SECOND_ENTER_AMOUNT);
    }
}