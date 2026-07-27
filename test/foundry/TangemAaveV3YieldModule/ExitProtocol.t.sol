// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "./AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";

contract ExitProtocolTest is AaveV3YieldModuleBase {
    YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployEnteredRevenueModule(owner);
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

    function test_exitProtocol_Reverts_WhenNetworkFeeExceedsMax() public {
        vm.expectRevert(IYieldModule.NetworkFeeExceedsMax.selector);
        vm.prank(backend);
        processor.exitProtocol(address(yieldModule), address(yieldToken), uint(DEFAULT_MAX_NETWORK_FEE) + 1);
    }

    function test_exitProtocol_Reverts_WhenNotProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        vm.prank(owner);
        yieldModule.exitProtocol(address(yieldToken), NETWORK_FEE);
    }

    function test_exitProtocol_Reverts_WhenTokenNotActive() public {
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);

        vm.prank(address(processor));
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

        _assertLatestFeePaymentState(yieldModule, INITIAL_OWNER_BALANCE, SERVICE_FEE_RATE);

        _exitViaProcessor(yieldModule, NETWORK_FEE);

        _assertLatestFeePaymentState(yieldModule, 0, newFeeRate);
    }

    function test_exitProtocol_TransfersServiceAndNetworkFeeFromOwnerToFeeReceiver() public {
        vm.expectEmit(address(yieldToken));
        emit IERC20.Transfer(owner, feeReceiver, ACCUMULATED_SERVICE_FEE + NETWORK_FEE);

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }

    function test_exitProtocol_EmitsFeePaymentProcessed() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), NETWORK_FEE + ACCUMULATED_SERVICE_FEE, feeReceiver);

        _exitViaProcessor(yieldModule, NETWORK_FEE);
    }
}
