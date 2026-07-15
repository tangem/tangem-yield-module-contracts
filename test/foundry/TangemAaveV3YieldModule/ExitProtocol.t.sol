// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract ExitProtocolTest is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;
    uint internal serviceFee;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployEnteredRevenueModule(owner);
        serviceFee = ACCUMULATED_SERVICE_FEE;
    }

    function test_exitProtocol_WithdrawsTotalProtocolBalanceToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(address(yieldToken), PROTOCOL_BALANCE, owner);

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_exitProtocol_DeactivatesYieldToken() public {
        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(active);

        _exitViaProcessor(yieldModule, NETWORK_FEE);

        (, active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }

    function test_exitProtocol_RevertsNetworkFeeExceedsMax() public {
        vm.expectRevert(IYieldModule.NetworkFeeExceedsMax.selector);
        vm.prank(backend);
        processor.exitProtocol(
            address(yieldModule), address(yieldToken), uint(DEFAULT_MAX_NETWORK_FEE) + 1
        );
    }

    function test_exitProtocol_RevertsOnlyProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        vm.prank(owner);
        yieldModule.exitProtocol(address(yieldToken), NETWORK_FEE);
    }

    function test_exitProtocol_EmitsProtocolExited() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.ProtocolExited(address(yieldToken), PROTOCOL_BALANCE, NETWORK_FEE);

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }

    /* Fee processing */

    function test_exitProtocol_SetsLatestFeePaymentState() public {
        uint newFeeRate = 300;
        _setServiceFeeRate(newFeeRate);

        (uint protocolBalance, uint serviceFeeRate) =
            yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, INITIAL_OWNER_BALANCE);
        assertEq(serviceFeeRate, SERVICE_FEE_RATE);

        _exitViaProcessor(yieldModule, NETWORK_FEE);

        (protocolBalance, serviceFeeRate) = yieldModule.latestFeePaymentStates(address(yieldToken));
        assertEq(protocolBalance, 0);
        assertEq(serviceFeeRate, newFeeRate);
    }

    function test_exitProtocol_TransfersServiceAndNetworkFeeFromOwnerToFeeReceiver() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, feeReceiver, serviceFee + NETWORK_FEE);

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_exitProtocol_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(
            address(yieldToken),
            NETWORK_FEE + serviceFee,
            feeReceiver
        );

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }
}
