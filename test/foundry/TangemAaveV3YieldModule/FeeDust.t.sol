// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";
import { AaveV3YieldModuleFixture } from "./AaveV3YieldModuleFixture.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";

contract FeeDustTest is AaveV3YieldModuleFixture {
    uint internal constant DUST = 3;
    uint internal constant SWAP_DEPOSIT = 100_000e6;
    uint internal constant SWAP_REVENUE = 10_000e6;

    YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployEnteredRevenueModule(owner);
    }

    /* withdraw */

    function testFuzz_withdraw_ChargesWholeBalanceLeftAsFeeWhenPullLeavesDust(uint dust) public {
        dust = bound(dust, 1, 1e6);
        pool.setWithdrawBurnShortfall(dust);

        // exact boundary: protocolBal == amount + fee
        uint amount = PROTOCOL_BALANCE - ACCUMULATED_SERVICE_FEE;

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, ACCUMULATED_SERVICE_FEE + dust);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), ACCUMULATED_SERVICE_FEE + dust, feeReceiver);

        _withdraw(yieldModule, owner, address(yieldToken), amount);

        _assertNothingLeftInModule(ACCUMULATED_SERVICE_FEE + dust);
    }

    /* send */

    function testFuzz_send_ChargesWholeBalanceLeftAsFeeWhenPullLeavesDust(uint dust) public {
        dust = bound(dust, 1, 1e6);
        pool.setWithdrawBurnShortfall(dust);

        uint ownerBalance = FRESH_OWNER_BALANCE;
        _mintYieldToken(owner, ownerBalance);

        // exact boundary: protocolBal == pullAmount + fee
        uint amount = ownerBalance + PROTOCOL_BALANCE - ACCUMULATED_SERVICE_FEE;

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, ACCUMULATED_SERVICE_FEE + dust);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), ACCUMULATED_SERVICE_FEE + dust, feeReceiver);

        vm.prank(owner);
        yieldModule.send(address(yieldToken), otherAccount, amount);

        assertEq(yieldToken.balanceOf(otherAccount), amount, "receiver balance");
        _assertNothingLeftInModule(ACCUMULATED_SERVICE_FEE + dust);
    }

    /* withdrawAndDeactivate */

    function testFuzz_withdrawAndDeactivate_ChargesWholeBalanceLeftAsFeeWhenPullLeavesDust(uint dust) public {
        dust = bound(dust, 1, 1e6);
        pool.setWithdrawBurnShortfall(dust);

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, ACCUMULATED_SERVICE_FEE + dust);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.WithdrawAndDeactivateProcessed(
            address(yieldToken),
            PROTOCOL_BALANCE - ACCUMULATED_SERVICE_FEE
        );

        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertFalse(active, "token still active");
        _assertNothingLeftInModule(ACCUMULATED_SERVICE_FEE + dust);
    }

    /* swap */

    function testFuzz_swap_ChargesWholeBalanceLeftAsFeeWhenPullLeavesDust(uint dust) public {
        dust = bound(dust, 1, 1e6);

        // separate module: the whole amountIn has to be pulled from the protocol
        YieldModuleHarness swapModule = _deployEnteredYieldModule(otherAccount, SWAP_DEPOSIT);
        _generateRevenue(address(swapModule), SWAP_REVENUE);
        _allowSwapProvider(address(swapProvider));

        uint fee = SWAP_REVENUE * SERVICE_FEE_RATE / PRECISION;
        // exact boundary: protocolBal == needed + feeIn
        uint amountIn = SWAP_DEPOSIT + SWAP_REVENUE - fee;

        pool.setWithdrawBurnShortfall(dust);

        bytes memory data = abi.encodeWithSelector(
            SwapProviderMock.swapExactIn.selector, address(yieldToken), address(0), amountIn, 0, backend
        );

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(swapModule), feeReceiver, fee + dust);
        vm.expectEmit(address(swapModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), fee + dust, feeReceiver);

        vm.prank(otherAccount);
        swapModule.swap(address(yieldToken), amountIn, address(swapProvider), address(0), data);

        assertEq(protocolToken.balanceOf(address(swapModule)), 0, "protocol dust left in module");
        assertEq(protocolToken.balanceOf(feeReceiver), fee + dust, "fee receiver balance");
        assertEq(swapModule.feeDebts(address(yieldToken)), 0, "fee debt");
    }

    /* helpers */

    function _assertNothingLeftInModule(uint expectedFee) internal view {
        assertEq(protocolToken.balanceOf(address(yieldModule)), 0, "protocol dust left in module");
        assertEq(protocolToken.balanceOf(feeReceiver), expectedFee, "fee receiver balance");
        assertEq(yieldModule.feeDebts(address(yieldToken)), 0, "fee debt");
        _assertLatestFeePaymentState(yieldModule, 0, SERVICE_FEE_RATE);
    }
}
