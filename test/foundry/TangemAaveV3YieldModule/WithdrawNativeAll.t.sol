// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { Requires } from "contracts/common/Requires.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract WithdrawNativeAllTest is TangemAaveV3YieldModuleBase {
    uint internal constant NATIVE_BALANCE = 0.001 ether;

    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_withdrawNativeAll_EmitsWithdrawNativeProcessedWithZeroAmountWhenBalanceIsZero() public {
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
