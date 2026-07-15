// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract EnterProtocolTest is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        _mintYieldToken(owner, INITIAL_OWNER_BALANCE);
        _mintYieldToken(address(yieldModule), INITIAL_MODULE_BALANCE);

        vm.prank(owner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    /// first enter without a network fee, then accumulate revenue and change the fee rate
    function _setupConsecutiveEnter() internal returns (uint serviceFee) {
        serviceFee = ACCUMULATED_REVENUE * SERVICE_FEE_RATE / PRECISION;

        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));

        _mintYieldToken(owner, FRESH_OWNER_BALANCE);
        _generateRevenue(address(yieldModule), ACCUMULATED_REVENUE);
        _setServiceFeeRate(NEW_FEE_RATE);
    }

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
}
