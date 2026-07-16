// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleBase } from "../YieldModuleBase.sol";
import { YieldModuleGenericHarness } from "../harnesses/YieldModuleGenericHarness.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";

contract CollectServiceFeeTest is YieldModuleBase {
    YieldModuleGenericHarness internal yieldModule;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();
        _registerGenericImplementation();

        yieldModule = _deployEnteredRevenueGenericModule(owner);
        serviceFee = ACCUMULATED_SERVICE_FEE;
    }

    function test_collectServiceFee_SetsLatestFeePaymentState() public {
        uint newFeeRate = 2_000;
        _setServiceFeeRate(newFeeRate);

        uint expectedProtocolBalance = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE - serviceFee;

        (uint protocolBalance, uint serviceFeeRate) =
            yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, INITIAL_OWNER_BALANCE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _collectViaProcessor(yieldModule);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, expectedProtocolBalance);
        assertEq(serviceFeeRate, newFeeRate);
    }

    function test_collectServiceFee_TransfersServiceFeeToFeeReceiver() public {
        address protocolTokenAddr = address(yieldModule.protocolTokens(address(yieldToken)));

        vm.expectEmit(protocolTokenAddr);
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);

        _collectViaProcessor(yieldModule);
    }

    function test_collectServiceFee_RevertsOnlyProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        vm.prank(owner);
        yieldModule.collectServiceFee(address(yieldToken));
    }

    function test_collectServiceFee_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), serviceFee, feeReceiver);

        _collectViaProcessor(yieldModule);
    }

    function test_collectServiceFee_RevertsNothingToCollect() public {
        YieldModuleGenericHarness yieldModule2 =
            _deployGenericYieldModuleWithFunds(otherAccount, 10_000e6);

        // first enter with zero network fee and no revenue => baseline sync only, nothing to collect
        _enterViaProcessor(yieldModule2, 0);

        vm.expectRevert(IYieldModule.NothingToCollect.selector);
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule2), address(yieldToken));
    }

    function test_collectServiceFee_RevertsFeeProcessingFailedWhenDebtExistsAndProtocolBalanceIsZero()
        public
    {
        YieldModuleGenericHarness yieldModule2 =
            _deployGenericYieldModuleWithFunds(otherAccount, 100_000e6);
        uint revenue = 10_000e6;

        _enterViaProcessor(yieldModule2, 0);
        _generateRevenue(address(yieldToken), address(yieldModule2), revenue);

        uint expectedFee = revenue * SERVICE_FEE_RATE / PRECISION;

        // force fee collection from owner to fail in exitProtocol => debt persists
        vm.prank(otherAccount);
        yieldToken.approve(address(yieldModule2), 0);

        vm.expectEmit(address(yieldModule2));
        emit IYieldModule.FeePaymentFailed(address(yieldToken), expectedFee);
        _exitViaProcessor(yieldModule2, 0);

        // fee debt > 0 passes NothingToCollect, but protocol balance == 0 => FeeProcessingFailed
        vm.expectRevert(IYieldModule.FeeProcessingFailed.selector);
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule2), address(yieldToken));
    }
}