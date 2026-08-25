// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";
import { AaveV3YieldModuleFixture } from "./AaveV3YieldModuleFixture.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { AaveV3PoolMock } from "contracts/test/AaveV3PoolMock.sol";
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

contract RiskServiceTest is AaveV3YieldModuleFixture {
    bytes32 internal constant POOL_WITHDRAW_EVENT_SIG = keccak256("Withdraw(address,uint256,address)");
    bytes32 internal constant POOL_SUPPLY_EVENT_SIG = keccak256("Supply(address,uint256,address,uint16)");
    bytes32 internal constant ENTRY_SUSPENSION_SET_EVENT_SIG = keccak256("EntrySuspensionSet(address,bool)");

    uint internal constant AVAILABLE_AFTER_FEE = PROTOCOL_BALANCE - ACCUMULATED_SERVICE_FEE;
    uint internal constant SOFT_EXIT_AMOUNT = 40_000e6;
    uint internal constant WITHDRAW_AMOUNT = 1_000e6;

    YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployEnteredRevenueModule(owner);
    }

    /*  softExit  */

    function test_softExit_WithdrawsProtocolBalanceMinusFeeToOwner() public {
        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(address(yieldToken), AVAILABLE_AFTER_FEE, owner);

        _softExitViaProcessor(yieldModule);

        assertEq(yieldToken.balanceOf(owner), AVAILABLE_AFTER_FEE);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), 0);
    }

    function test_softExit_KeepsTokenActive() public {
        _softExitViaProcessor(yieldModule);

        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(active);
    }

    function test_softExit_SetsEntrySuspended() public {
        assertFalse(yieldModule.entrySuspended(address(yieldToken)));

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.EntrySuspensionSet(address(yieldToken), true);

        _softExitViaProcessor(yieldModule);

        assertTrue(yieldModule.entrySuspended(address(yieldToken)));
    }

    function test_softExit_EmitsSoftExitTriggered() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SoftExitTriggered(address(yieldToken), PROTOCOL_BALANCE, AVAILABLE_AFTER_FEE);

        _softExitViaProcessor(yieldModule);
    }

    function test_softExit_ChargesAccruedServiceFee() public {
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, ACCUMULATED_SERVICE_FEE);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(yieldToken), ACCUMULATED_SERVICE_FEE, feeReceiver);

        _softExitViaProcessor(yieldModule);

        _assertLatestFeePaymentState(yieldModule, 0, SERVICE_FEE_RATE);
    }

    function test_softExit_DoesNotWithdraw_WhenProtocolBalanceIsZero() public {
        _withdraw(yieldModule, owner, address(yieldToken), AVAILABLE_AFTER_FEE);
        assertEq(yieldModule.protocolBalance(address(yieldToken)), 0);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SoftExitTriggered(address(yieldToken), 0, 0);

        vm.recordLogs();
        _softExitViaProcessor(yieldModule);

        _assertEventNotEmitted(vm.getRecordedLogs(), POOL_WITHDRAW_EVENT_SIG);
        assertTrue(yieldModule.entrySuspended(address(yieldToken)));
    }

    function test_softExit_KeepsResidualFeeDebt_WhenFeeExceedsProtocolBalance() public {
        address debtOwner = makeAddr("debtOwner");
        (YieldModuleHarness debtModule, uint feeDebt) = _createFeeDebtState(debtOwner);

        uint recoveredBalance = feeDebt / 2;
        _generateRevenue(address(yieldToken), address(debtModule), recoveredBalance);

        uint expectedFee = feeDebt + recoveredBalance * SERVICE_FEE_RATE / PRECISION;
        uint expectedDebt = expectedFee - recoveredBalance;

        vm.expectEmit(address(debtModule));
        emit IYieldModule.FeePaymentPartial(address(yieldToken), recoveredBalance, expectedDebt, feeReceiver);
        vm.expectEmit(address(debtModule));
        emit IYieldModule.SoftExitTriggered(address(yieldToken), recoveredBalance, 0);

        _softExitViaProcessor(debtModule);

        assertEq(yieldToken.balanceOf(debtOwner), 0);
        assertEq(debtModule.protocolBalance(address(yieldToken)), 0);
        assertEq(debtModule.feeDebts(address(yieldToken)), expectedDebt);
        assertTrue(debtModule.entrySuspended(address(yieldToken)));
    }

    function test_softExit_DoesNotReemitEntrySuspensionSet_WhenTokenEntrySuspended() public {
        _suspendViaProcessor(yieldModule);

        vm.recordLogs();
        _softExitViaProcessor(yieldModule);

        _assertEventNotEmitted(vm.getRecordedLogs(), ENTRY_SUSPENSION_SET_EVENT_SIG);
    }

    function test_softExit_ReportsTokenNotActive_WhenTokenNotActive() public {
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.SoftExitProcessed(
            address(yieldModule),
            address(yieldToken),
            type(uint).max,
            IYieldModule.SoftExitResult.TOKEN_NOT_ACTIVE,
            ""
        );

        _softExitViaProcessor(yieldModule);
    }

    function test_softExit_ReportsPullFailed_WhenProtocolPullReverts() public {
        pool.setFailWithdraw(true);

        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.SoftExitProcessed(
            address(yieldModule),
            address(yieldToken),
            type(uint).max,
            IYieldModule.SoftExitResult.PULL_FAILED,
            abi.encodeWithSelector(AaveV3PoolMock.WithdrawFailed.selector)
        );

        _softExitViaProcessor(yieldModule);

        // the suspension is the point of a soft exit: it must survive a failing pool
        assertTrue(yieldModule.entrySuspended(address(yieldToken)), "entry suspended");
        assertEq(yieldModule.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE, "protocol");
        assertEq(protocolToken.balanceOf(feeReceiver), 0, "fee");
    }

    function testFuzz_softExit_ClampsAmountToBalanceAvailableAfterFee(uint deposit, uint revenue, uint amount) public {
        deposit = bound(deposit, 1, type(uint128).max);
        revenue = bound(revenue, 0, type(uint128).max);

        address fuzzOwner = makeAddr("fuzzOwner");
        YieldModuleHarness fuzzModule = _deployYieldModuleWithFunds(fuzzOwner, deposit);
        _enterViaProcessor(fuzzModule, 0);
        _generateRevenue(address(yieldToken), address(fuzzModule), revenue);

        _mintYieldToken(address(pool), revenue);

        uint expectedFee = revenue * SERVICE_FEE_RATE / PRECISION;
        uint availableAfterFee = deposit + revenue - expectedFee;
        amount = bound(amount, 1, 2 * (deposit + revenue));
        uint expectedExit = amount > availableAfterFee ? availableAfterFee : amount;

        vm.expectEmit(address(fuzzModule));
        emit IYieldModule.SoftExitTriggered(address(yieldToken), deposit + revenue, expectedExit);

        _softExitViaProcessor(fuzzModule, amount);

        assertEq(yieldToken.balanceOf(fuzzOwner), expectedExit, "owner");
        assertEq(fuzzModule.protocolBalance(address(yieldToken)), availableAfterFee - expectedExit, "protocol");
        assertEq(protocolToken.balanceOf(feeReceiver), expectedFee, "fee");
    }

    function test_softExitAmount_ReportsZeroAmount_WhenAmountIsZero() public {
        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.SoftExitProcessed(
            address(yieldModule),
            address(yieldToken),
            0,
            IYieldModule.SoftExitResult.ZERO_AMOUNT,
            ""
        );

        _softExitViaProcessor(yieldModule, 0);

        assertFalse(yieldModule.entrySuspended(address(yieldToken)), "entry suspension untouched");
    }

    /*  suspendToken  */

    function test_suspendToken_SuspendsEntryWithoutWithdrawing() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.EntrySuspensionSet(address(yieldToken), true);

        _suspendViaProcessor(yieldModule);

        assertTrue(yieldModule.entrySuspended(address(yieldToken)));
        assertEq(yieldModule.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    function test_suspendToken_Reverts_WhenTokenEntrySuspended() public {
        _suspendViaProcessor(yieldModule);

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        _suspendViaProcessor(yieldModule);
    }

    function test_suspendToken_Reverts_WhenTokenNotActive() public {
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        _suspendViaProcessor(yieldModule);
    }

    /*  resumeAndEnterProtocol  */

    function test_resumeAndEnterProtocol_ClearsEntrySuspension() public {
        _suspendViaProcessor(yieldModule);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.EntrySuspensionSet(address(yieldToken), false);

        _resumeViaProcessor(yieldModule);

        assertFalse(yieldModule.entrySuspended(address(yieldToken)));
    }

    function test_resumeAndEnterProtocol_EntersProtocolWithFullOwnerBalance() public {
        _softExitViaProcessor(yieldModule);

        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(yieldToken), AVAILABLE_AFTER_FEE, address(yieldModule), 0);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.ProtocolEntered(address(yieldToken), AVAILABLE_AFTER_FEE, 0);

        _resumeViaProcessor(yieldModule);

        assertEq(yieldModule.protocolBalance(address(yieldToken)), AVAILABLE_AFTER_FEE);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    function test_resumeAndEnterProtocol_SkipsEntry_WhenOwnerBalanceIsZero() public {
        _suspendViaProcessor(yieldModule);

        vm.recordLogs();
        _resumeViaProcessor(yieldModule);

        _assertEventNotEmitted(vm.getRecordedLogs(), POOL_SUPPLY_EVENT_SIG);
        assertFalse(yieldModule.entrySuspended(address(yieldToken)));
        assertEq(yieldModule.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE);
    }

    function test_resumeAndEnterProtocol_KeepsSuspension_WhenProtocolEntryReverts() public {
        _softExitViaProcessor(yieldModule);
        pool.setFailSupply(true);

        vm.expectRevert(AaveV3PoolMock.SupplyFailed.selector);
        _resumeViaProcessor(yieldModule);

        assertTrue(yieldModule.entrySuspended(address(yieldToken)));
    }

    function test_resumeAndEnterProtocol_Reverts_WhenNotEntrySuspended() public {
        vm.expectRevert(IYieldModule.NotEntrySuspended.selector);
        _resumeViaProcessor(yieldModule);
    }

    function test_resumeAndEnterProtocol_Reverts_WhenTokenNotActive() public {
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        _resumeViaProcessor(yieldModule);
    }

    /*  Entry gating  */

    function test_EntrySuspension_BlocksProcessorEntry() public {
        _suspendViaProcessor(yieldModule);

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        _enterViaProcessor(yieldModule, 0);
    }

    function test_EntrySuspension_BlocksOwnerEntry() public {
        _suspendViaProcessor(yieldModule);

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    function test_EntrySuspension_AllowsOwnerWithdraw() public {
        _softExitViaProcessor(yieldModule, SOFT_EXIT_AMOUNT);

        _withdraw(yieldModule, owner, address(yieldToken), WITHDRAW_AMOUNT);

        assertEq(yieldToken.balanceOf(owner), SOFT_EXIT_AMOUNT + WITHDRAW_AMOUNT);
    }

    function test_EntrySuspension_RoutesSwapOutputToReceiver() public {
        uint amountIn = 1_000e6;
        uint amountOut = 500e18;

        TestERC20 tokenOut = _deployTestToken();
        vm.prank(owner);
        yieldModule.initYieldToken(address(tokenOut), 0);
        _suspendViaProcessor(yieldModule, address(tokenOut));

        _allowSwapProvider(address(swapProvider));
        _mintYieldToken(owner, amountIn);
        _mintToken(tokenOut, address(swapProvider), amountOut);

        vm.expectEmit(address(tokenOut));
        emit IERC20.Transfer(address(yieldModule), otherAccount, amountOut);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapAndReceiveCompleted(address(tokenOut), otherAccount, amountOut, false);

        vm.prank(owner);
        yieldModule.swapAndReceive(
            address(yieldToken),
            address(tokenOut),
            otherAccount,
            amountIn,
            address(swapProvider),
            address(0),
            _swapExactInData(address(tokenOut), amountIn, amountOut)
        );

        assertEq(tokenOut.balanceOf(otherAccount), amountOut);
    }

    /*  Inactive token gaps  */

    function test_EntrySuspension_DoesNotCoverNewlyInitializedToken() public {
        _suspendViaProcessor(yieldModule);

        uint deposit = 1_000e18;
        TestERC20 freshToken = _deployTestToken();
        _mintToken(freshToken, owner, deposit);

        vm.startPrank(owner);
        yieldModule.initYieldToken(address(freshToken), 0);
        freshToken.approve(address(yieldModule), type(uint).max);
        vm.stopPrank();

        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(freshToken), deposit, address(yieldModule), 0);

        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(freshToken));

        assertFalse(yieldModule.entrySuspended(address(freshToken)));
        assertEq(freshToken.balanceOf(owner), 0);
    }

    function test_EntrySuspension_DoesNotCoverTokenReactivatedAfterExit() public {
        _exitViaProcessor(yieldModule, 0);

        uint exitedBalance = yieldToken.balanceOf(owner);

        vm.startPrank(owner);
        yieldModule.reactivateToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
        yieldModule.enterProtocolByOwner(address(yieldToken));
        vm.stopPrank();

        assertFalse(yieldModule.entrySuspended(address(yieldToken)));
        assertEq(yieldModule.protocolBalance(address(yieldToken)), exitedBalance);
    }

    function test_EntrySuspension_PersistsThroughReactivation() public {
        _softExitViaProcessor(yieldModule);
        _withdrawAndDeactivate(yieldModule, owner, address(yieldToken));

        vm.prank(owner);
        yieldModule.reactivateToken(address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        assertTrue(yieldModule.entrySuspended(address(yieldToken)));

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(address(yieldToken));
    }

    /*  Access control  */

    function test_RiskFunctions_Revert_WhenNotProcessor() public {
        vm.startPrank(owner);

        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        yieldModule.softExit(address(yieldToken));

        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        yieldModule.softExit(address(yieldToken), SOFT_EXIT_AMOUNT);

        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        yieldModule.suspendToken(address(yieldToken));

        vm.expectRevert(IYieldModule.OnlyProcessor.selector);
        yieldModule.resumeAndEnterProtocol(address(yieldToken));

        vm.stopPrank();
    }

    /*  helpers  */

    function _swapExactInData(address tokenOut, uint amountIn, uint amountOut) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            SwapProviderMock.swapExactIn.selector, address(yieldToken), tokenOut, amountIn, amountOut, backend
        );
    }
}
