// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { Requires } from "contracts/common/Requires.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { NativeRejectingOwner } from "contracts/test/NativeRejectingOwner.sol";
import { AaveV3YieldModuleFixture } from "test/foundry/TangemAaveV3YieldModule/AaveV3YieldModuleFixture.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";

contract NativeSupportTest is AaveV3YieldModuleFixture {
    uint internal constant DEPOSIT = 10 ether;
    uint internal constant WITHDRAW_AMOUNT = 4 ether;
    uint internal constant REVENUE = 1 ether;
    uint internal constant SERVICE_FEE = REVENUE * SERVICE_FEE_RATE / PRECISION;

    TangemAaveV3YieldModuleHarness internal ym;

    function setUp() public override {
        super.setUp();

        ym = _deployNativeModule(owner);
        vm.deal(owner, DEPOSIT);
    }

    /*  enterProtocolByOwnerWithNative  */

    function test_enterWithNative_WrapsValueAndSuppliesPool() public {
        vm.expectEmit(address(ym));
        emit IYieldModule.ProtocolEntered(address(wrappedNative), DEPOSIT, 0);

        _enterWithNative(ym, owner, DEPOSIT);

        assertEq(ym.protocolBalance(address(wrappedNative)), DEPOSIT, "protocol balance");
        assertEq(wrappedNative.balanceOf(address(pool)), DEPOSIT, "pool wrapped balance");
        assertEq(address(ym).balance, 0, "module native residue");
        assertEq(wrappedNative.balanceOf(address(ym)), 0, "module wrapped residue");
    }

    // both the native and the wrapped token stuck on the module are swept in along with msg.value
    function test_enterWithNative_PicksUpStuckModuleBalances() public {
        uint stuckNative = 1 ether;
        uint stuckWrapped = 2 ether;

        vm.deal(address(ym), stuckNative);
        _mintWrappedNative(address(ym), stuckWrapped);

        vm.expectEmit(address(ym));
        emit IYieldModule.ProtocolEntered(address(wrappedNative), DEPOSIT + stuckNative + stuckWrapped, 0);

        _enterWithNative(ym, owner, DEPOSIT);

        assertEq(ym.protocolBalance(address(wrappedNative)), DEPOSIT + stuckNative + stuckWrapped, "protocol balance");
    }

    function test_enterWithNative_Reverts_WhenNothingToDeposit() public {
        vm.expectRevert(Requires.ZeroAmount.selector);
        _enterWithNative(ym, owner, 0);
    }

    function test_enterWithNative_Reverts_WhenTokenNotActive() public {
        TangemAaveV3YieldModuleHarness noTokenModule =
            TangemAaveV3YieldModuleHarness(payable(address(_deployYieldModule(otherAccount, address(0), 0))));

        vm.deal(otherAccount, DEPOSIT);

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        vm.prank(otherAccount);
        noTokenModule.enterProtocolByOwnerWithNative{ value: DEPOSIT }();
    }

    function test_enterWithNative_Reverts_WhenEntrySuspended() public {
        _suspendViaProcessor(ym, address(wrappedNative));

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        _enterWithNative(ym, owner, DEPOSIT);
    }

    /*  withdrawNative  */

    function test_withdrawNative_UnwrapsAndSendsToOwner() public {
        _enterWithNative(ym, owner, DEPOSIT);

        vm.expectEmit(address(ym));
        emit IYieldModule.WithdrawProcessed(address(wrappedNative), WITHDRAW_AMOUNT);

        vm.prank(owner);
        ym.withdrawNative(WITHDRAW_AMOUNT);

        assertEq(owner.balance, WITHDRAW_AMOUNT, "owner native balance");
        assertEq(ym.protocolBalance(address(wrappedNative)), DEPOSIT - WITHDRAW_AMOUNT, "protocol balance");
        assertEq(address(ym).balance, 0, "module native residue");
        assertEq(wrappedNative.balanceOf(address(ym)), 0, "module wrapped residue");
    }

    function test_withdrawNative_ChargesServiceFeeInProtocolToken() public {
        _enterWithNativeWithRevenue();

        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(ym), feeReceiver, SERVICE_FEE);

        vm.prank(owner);
        ym.withdrawNative(WITHDRAW_AMOUNT);

        assertEq(owner.balance, WITHDRAW_AMOUNT, "owner native balance");
        assertEq(protocolToken.balanceOf(feeReceiver), SERVICE_FEE, "fee receiver balance");
        assertEq(
            ym.protocolBalance(address(wrappedNative)),
            DEPOSIT + REVENUE - WITHDRAW_AMOUNT - SERVICE_FEE,
            "protocol balance"
        );
    }

    function test_withdrawNative_Reverts_WhenAmountPlusFeeExceedsProtocolBalance() public {
        _enterWithNativeWithRevenue();

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        vm.prank(owner);
        ym.withdrawNative(DEPOSIT + REVENUE - SERVICE_FEE + 1);
    }

    function test_withdrawNative_Reverts_WhenOwnerRejectsNative() public {
        address rejectingOwner = address(new NativeRejectingOwner());
        TangemAaveV3YieldModuleHarness rejectingModule = _deployNativeModule(rejectingOwner);

        vm.deal(rejectingOwner, DEPOSIT);
        _enterWithNative(rejectingModule, rejectingOwner, DEPOSIT);

        vm.expectRevert(IYieldModule.NativeTransferFailed.selector);
        vm.prank(rejectingOwner);
        rejectingModule.withdrawNative(WITHDRAW_AMOUNT);
    }

    /*  withdrawAndDeactivateNative  */

    function test_withdrawAndDeactivateNative_PaysOutNetOfFeeAndDeactivates() public {
        _enterWithNativeWithRevenue();

        uint expectedPayout = DEPOSIT + REVENUE - SERVICE_FEE;

        vm.expectEmit(address(ym));
        emit IYieldModule.WithdrawAndDeactivateProcessed(address(wrappedNative), expectedPayout);

        vm.prank(owner);
        ym.withdrawAndDeactivateNative();

        assertEq(owner.balance, expectedPayout, "owner native balance");
        assertEq(protocolToken.balanceOf(feeReceiver), SERVICE_FEE, "fee receiver balance");
        assertEq(ym.protocolBalance(address(wrappedNative)), 0, "protocol balance");
        _assertTokenActive(false);
    }

    function test_withdrawAndDeactivateNative_DeactivatesWhenProtocolBalanceIsZero() public {
        vm.expectEmit(address(ym));
        emit IYieldModule.WithdrawAndDeactivateProcessed(address(wrappedNative), 0);

        vm.prank(owner);
        ym.withdrawAndDeactivateNative();

        assertEq(owner.balance, DEPOSIT, "owner native balance untouched");
        _assertTokenActive(false);
    }

    /*  Access control  */

    function test_nativeFunctions_Revert_WhenNotOwner() public {
        vm.deal(otherAccount, DEPOSIT);
        vm.startPrank(otherAccount);

        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        ym.enterProtocolByOwnerWithNative{ value: DEPOSIT }();

        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        ym.withdrawNative(WITHDRAW_AMOUNT);

        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        ym.withdrawAndDeactivateNative();

        vm.stopPrank();
    }

    /*  Constructor  */

    function test_constructor_Reverts_WhenWrappedNativeIsZero() public {
        vm.expectRevert(Requires.ZeroAddress.selector);

        new TangemAaveV3YieldModuleHarness(
            address(pool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry),
            address(0)
        );
    }

    /*  Helpers  */

    function _deployNativeModule(address moduleOwner) internal returns (TangemAaveV3YieldModuleHarness) {
        return TangemAaveV3YieldModuleHarness(
            payable(address(_deployYieldModule(moduleOwner, address(wrappedNative), DEFAULT_MAX_NETWORK_FEE)))
        );
    }

    function _enterWithNative(TangemAaveV3YieldModuleHarness module, address moduleOwner, uint amount) internal {
        vm.prank(moduleOwner);
        module.enterProtocolByOwnerWithNative{ value: amount }();
    }

    /// Enters with DEPOSIT and generates REVENUE, keeping the pool solvent for the full payout.
    function _enterWithNativeWithRevenue() internal {
        _enterWithNative(ym, owner, DEPOSIT);

        _generateRevenue(address(ym), REVENUE);
        _mintWrappedNative(address(pool), REVENUE);
    }

    function _mintWrappedNative(address to, uint amount) internal {
        vm.deal(backend, amount);

        vm.startPrank(backend);
        wrappedNative.deposit{ value: amount }();
        wrappedNative.transfer(to, amount);
        vm.stopPrank();
    }

    function _assertTokenActive(bool expected) internal view {
        (, bool active,) = ym.yieldTokensData(address(wrappedNative));
        assertEq(active, expected, "token active");
    }
}
