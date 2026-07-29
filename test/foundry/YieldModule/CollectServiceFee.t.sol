// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract CollectServiceFeeTest is YieldModuleFixture {
    YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();

        yieldModule = _deployEnteredRevenueModule(owner);
    }

    function test_collectServiceFee_SetsLatestFeePaymentState() public {
        uint newFeeRate = 2_000;
        _setServiceFeeRate(newFeeRate);

        uint expectedProtocolBalance = INITIAL_OWNER_BALANCE + ACCUMULATED_REVENUE - ACCUMULATED_SERVICE_FEE;

        _assertLatestFeePaymentState(yieldModule, INITIAL_OWNER_BALANCE, SERVICE_FEE_RATE);

        _collectViaProcessor(yieldModule);

        _assertLatestFeePaymentState(yieldModule, expectedProtocolBalance, newFeeRate);
    }

    function test_collectServiceFee_TransfersServiceFeeToFeeReceiver() public {
        address protocolTokenAddr = address(yieldModule.protocolTokens(address(yieldToken)));

        vm.expectEmit(protocolTokenAddr);
        emit IERC20.Transfer(address(yieldModule), feeReceiver, ACCUMULATED_SERVICE_FEE);

        _collectViaProcessor(yieldModule);
    }

    function test_collectServiceFee_Reverts_WhenNotProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        vm.prank(owner);
        yieldModule.collectServiceFee(address(yieldToken));
    }

    function test_collectServiceFee_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), ACCUMULATED_SERVICE_FEE, feeReceiver);

        _collectViaProcessor(yieldModule);
    }

    function test_collectServiceFee_Reverts_WhenNothingToCollect() public {
        YieldModuleHarness yieldModule2 = _deployYieldModuleWithFunds(otherAccount, 10_000e6);

        // first enter with zero network fee and no revenue => baseline sync only, nothing to collect
        _enterViaProcessor(yieldModule2, 0);

        vm.expectRevert(IYieldModule.NothingToCollect.selector);
        vm.prank(backend);
        processor.collectServiceFee(address(yieldModule2), address(yieldToken));
    }

    function test_collectServiceFee_Reverts_WhenDebtExistsAndProtocolBalanceIsZero() public {
        YieldModuleHarness yieldModule2 = _deployYieldModuleWithFunds(otherAccount, 100_000e6);
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
