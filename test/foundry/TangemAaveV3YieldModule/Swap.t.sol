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
import { SwapProviderMock } from "contracts/test/SwapProviderMock.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";

abstract contract SwapTestBase is TangemAaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness internal yieldModule;
    address internal tokenIn;

    function setUp() public virtual override {
        super.setUp();

        tokenIn = address(yieldToken);
        yieldModule = _deployYieldModule(owner, tokenIn, DEFAULT_MAX_NETWORK_FEE);

        _allowSwapProvider(address(swapProvider));

        vm.prank(owner);
        yieldToken.approve(address(yieldModule), type(uint).max);
    }

    function _revertEmptyData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SwapProviderMock.revertEmpty.selector);
    }

    function _swapExactInData(
        address tokenOut,
        uint amountIn,
        uint amountOut
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            SwapProviderMock.swapExactIn.selector, tokenIn, tokenOut, amountIn, amountOut, backend
        );
    }
}

contract SwapTest is SwapTestBase {
    function _swap(uint amountIn, bytes memory data) internal {
        vm.prank(owner);
        yieldModule.swap(tokenIn, amountIn, address(swapProvider), address(0), data);
    }

    function test_swap_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(backend);
        yieldModule.swap(tokenIn, 1e6, address(swapProvider), address(0), _revertEmptyData());
    }

    function test_swap_RevertsTokenNotActive() public {
        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(tokenIn);

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        _swap(1e6, _revertEmptyData());
    }

    function test_swap_RevertsDataTooShort() public {
        vm.expectRevert(IYieldModule.DataTooShort.selector);
        _swap(1e6, hex"123456");
    }

    function test_swap_RevertsTargetHasNoCode() public {
        vm.expectRevert(IYieldModule.TargetHasNoCode.selector);
        vm.prank(owner);
        yieldModule.swap(tokenIn, 1e6, otherAccount, address(0), hex"12345678");
    }

    function test_swap_RevertsTargetNotAllowed() public {
        SwapProviderMock notAllowedProvider = new SwapProviderMock();

        vm.expectRevert(IYieldModule.TargetNotAllowed.selector);
        vm.prank(owner);
        yieldModule.swap(tokenIn, 1e6, address(notAllowedProvider), address(0), _revertEmptyData());
    }

    function test_swap_RevertsSpenderNotAllowed() public {
        vm.expectRevert(IYieldModule.SpenderNotAllowed.selector);
        vm.prank(owner);
        yieldModule.swap(tokenIn, 1e6, address(swapProvider), otherAccount, _revertEmptyData());
    }

    function test_swap_BubblesProviderCustomError() public {
        _mintYieldToken(owner, 1e6);

        vm.expectRevert(SwapProviderMock.MockRevert.selector);
        _swap(1e6, abi.encodeWithSelector(SwapProviderMock.revertWithError.selector));
    }

    function test_swap_RevertsProviderCallFailedWhenProviderRevertsWithoutData() public {
        _mintYieldToken(owner, 1e6);

        vm.expectRevert(IYieldModule.ProviderCallFailed.selector);
        _swap(1e6, _revertEmptyData());
    }

    function test_swap_LeavesTokenInResidueOnModuleAfterPartialSwap() public {
        uint amountIn = 1_000e6;
        _mintYieldToken(owner, amountIn);

        // spendPartial spends amountIn - 1, leaving 1 wei residue on the module
        bytes memory data = abi.encodeWithSelector(
            SwapProviderMock.spendPartial.selector, tokenIn, amountIn, backend
        );

        _swap(amountIn, data);

        assertEq(yieldToken.balanceOf(address(yieldModule)), 1);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    function test_swap_ExecutesSwapClearsAllowanceAndEmitsSwapInitiated() public {
        uint amountIn = 2_000e6;
        _mintYieldToken(owner, amountIn);

        uint sinkBalanceBefore = yieldToken.balanceOf(backend);
        bytes memory data = _swapExactInData(address(0), amountIn, 0);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapInitiated(
            tokenIn,
            amountIn,
            address(swapProvider),
            address(swapProvider),
            0,
            keccak256(data)
        );

        _swap(amountIn, data);

        assertEq(yieldToken.allowance(address(yieldModule), address(swapProvider)), 0);
        assertEq(yieldToken.balanceOf(address(yieldModule)), 0);
        assertEq(yieldToken.balanceOf(backend) - sinkBalanceBefore, amountIn);
    }

    function test_swap_PullsFromProtocolWhenOwnerBalanceInsufficientAndProcessesServiceFee()
        public
    {
        uint depositAmount = 100_000e6;
        uint accumulatedRevenue = 10_000e6;
        uint ownerTopup = 500e6;
        uint amountIn = 2_000e6;

        _mintYieldToken(owner, depositAmount);
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(tokenIn);
        _generateRevenue(address(yieldModule), accumulatedRevenue);

        uint serviceFee = accumulatedRevenue * SERVICE_FEE_RATE / PRECISION;

        _mintYieldToken(owner, ownerTopup);
        uint pullAmount = amountIn - ownerTopup;

        bytes memory data = _swapExactInData(address(0), amountIn, 0);

        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Withdraw(tokenIn, pullAmount, address(yieldModule));
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, serviceFee);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(tokenIn, serviceFee, feeReceiver);

        _swap(amountIn, data);
    }

    function test_swap_RevertsInsufficientFundsWhenPullAmountExceedsProtocolBalanceMinusFee()
        public
    {
        uint depositAmount = 1_000e6;
        uint ownerTopup = 500e6;
        uint amountIn = 2_000e6;

        _mintYieldToken(owner, depositAmount);
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(tokenIn);

        _mintYieldToken(owner, ownerTopup);

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        _swap(amountIn, _revertEmptyData());
    }

    /// Seeds the three funding sources independently: protocol first (via owner enter),
    /// then module residue and fresh owner balance. No revenue => service fee is zero.
    function _seedFundingSources(uint moduleBalance, uint ownerBalance, uint protocolBalance) internal {
        _mintYieldToken(owner, protocolBalance);
        vm.prank(owner);
        yieldModule.enterProtocolByOwner(tokenIn);

        _mintYieldToken(address(yieldModule), moduleBalance);
        _mintYieldToken(owner, ownerBalance);
    }

    // _prepareSwap funds the swap from module residue first, then owner, then protocol
    function testFuzz_swap_FundsFromModuleThenOwnerThenProtocol(
        uint amountIn,
        uint moduleBalance,
        uint ownerBalance,
        uint protocolBalance
    ) public {
        moduleBalance = bound(moduleBalance, 0, 10_000e6);
        ownerBalance = bound(ownerBalance, 0, 10_000e6);
        protocolBalance = bound(protocolBalance, 1, 100_000e6);
        amountIn = bound(amountIn, 1, moduleBalance + ownerBalance + protocolBalance);

        _seedFundingSources(moduleBalance, ownerBalance, protocolBalance);

        uint fromModule = amountIn < moduleBalance ? amountIn : moduleBalance;
        uint fromOwner = amountIn - fromModule < ownerBalance ? amountIn - fromModule : ownerBalance;
        uint fromProtocol = amountIn - fromModule - fromOwner;

        uint sinkBalanceBefore = yieldToken.balanceOf(backend);

        _swap(amountIn, _swapExactInData(address(0), amountIn, 0));

        assertEq(yieldToken.balanceOf(backend) - sinkBalanceBefore, amountIn, "sink");
        assertEq(yieldToken.balanceOf(address(yieldModule)), moduleBalance - fromModule, "module");
        assertEq(yieldToken.balanceOf(owner), ownerBalance - fromOwner, "owner");
        assertEq(yieldModule.protocolBalance(tokenIn), protocolBalance - fromProtocol, "protocol");
        assertEq(yieldToken.allowance(address(yieldModule), address(swapProvider)), 0, "allowance");
    }

    function testFuzz_swap_RevertsInsufficientFundsWhenSourcesCannotCoverAmount(
        uint amountIn,
        uint moduleBalance,
        uint ownerBalance,
        uint protocolBalance
    ) public {
        moduleBalance = bound(moduleBalance, 0, 10_000e6);
        ownerBalance = bound(ownerBalance, 0, 10_000e6);
        protocolBalance = bound(protocolBalance, 1, 100_000e6);
        uint total = moduleBalance + ownerBalance + protocolBalance;
        amountIn = bound(amountIn, total + 1, 2 * total);

        _seedFundingSources(moduleBalance, ownerBalance, protocolBalance);

        vm.expectRevert(IYieldModule.InsufficientFunds.selector);
        _swap(amountIn, _revertEmptyData());
    }
}

contract SwapAndReceiveTest is SwapTestBase {
    function _swapAndReceive(
        address tokenOut,
        address to,
        uint amountIn,
        bytes memory data
    ) internal {
        vm.prank(owner);
        yieldModule.swapAndReceive(
            tokenIn, tokenOut, to, amountIn, address(swapProvider), address(0), data
        );
    }

    function test_swapAndReceive_RevertsOnlyOwner() public {
        TestERC20 outToken = _deployTestToken();

        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(backend);
        yieldModule.swapAndReceive(
            tokenIn,
            address(outToken),
            otherAccount,
            1e6,
            address(swapProvider),
            address(0),
            _swapExactInData(address(outToken), 1e6, 0)
        );
    }

    function test_swapAndReceive_RevertsZeroAddressWhenTokenOutIsZero() public {
        vm.expectRevert(Requires.ZeroAddress.selector);
        _swapAndReceive(address(0), otherAccount, 1e6, _swapExactInData(address(0), 1e6, 0));
    }

    function test_swapAndReceive_RevertsTokenInEqualsTokenOut() public {
        vm.expectRevert(IYieldModule.TokenInEqualsTokenOut.selector);
        _swapAndReceive(tokenIn, otherAccount, 1e6, _swapExactInData(tokenIn, 1e6, 0));
    }

    function test_swapAndReceive_RevertsWithdrawingProtocolTokenWhenTokenOutIsProtocolToken()
        public
    {
        vm.expectRevert(IYieldModule.WithdrawingProtocolToken.selector);
        _swapAndReceive(
            address(protocolToken),
            otherAccount,
            1e6,
            _swapExactInData(address(protocolToken), 1e6, 0)
        );
    }

    function test_swapAndReceive_RevertsSwapPayoutNotReceived() public {
        TestERC20 outToken = _deployTestToken();
        uint amountIn = 1_000e6;

        _mintYieldToken(owner, amountIn);

        vm.expectRevert(IYieldModule.SwapPayoutNotReceived.selector);
        _swapAndReceive(
            address(outToken),
            otherAccount,
            amountIn,
            _swapExactInData(address(outToken), amountIn, 0)
        );
    }

    function test_swapAndReceive_RevertsZeroAddressWhenTokenOutNotActiveAndReceiverIsZero() public {
        TestERC20 outToken = _deployTestToken();
        uint amountIn = 1_000e6;
        uint amountOut = 500e6;

        _mintYieldToken(owner, amountIn);
        _mintToken(outToken, address(swapProvider), amountOut);

        vm.expectRevert(Requires.ZeroAddress.selector);
        _swapAndReceive(
            address(outToken),
            address(0),
            amountIn,
            _swapExactInData(address(outToken), amountIn, amountOut)
        );
    }

    function test_swapAndReceive_RevertsSendingToThisWhenReceiverIsModule() public {
        TestERC20 outToken = _deployTestToken();
        uint amountIn = 1_000e6;
        uint amountOut = 500e6;

        _mintYieldToken(owner, amountIn);
        _mintToken(outToken, address(swapProvider), amountOut);

        vm.expectRevert(IYieldModule.SendingToThis.selector);
        _swapAndReceive(
            address(outToken),
            address(yieldModule),
            amountIn,
            _swapExactInData(address(outToken), amountIn, amountOut)
        );
    }

    function test_swapAndReceive_TransfersTokenOutToReceiverWhenTokenOutNotActive() public {
        TestERC20 outToken = _deployTestToken();
        uint amountIn = 1_000e6;
        uint amountOut = 500e6;

        _mintYieldToken(owner, amountIn);
        _mintToken(outToken, address(swapProvider), amountOut);

        uint receiverBalanceBefore = outToken.balanceOf(otherAccount);
        bytes memory data = _swapExactInData(address(outToken), amountIn, amountOut);

        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapAndReceiveInitiated(
            tokenIn,
            address(outToken),
            otherAccount,
            amountIn,
            address(swapProvider),
            address(swapProvider),
            0,
            keccak256(data)
        );
        vm.expectEmit(address(outToken));
        emit IERC20.Transfer(address(yieldModule), otherAccount, amountOut);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapAndReceiveCompleted(address(outToken), otherAccount, amountOut, false);

        _swapAndReceive(address(outToken), otherAccount, amountIn, data);

        assertEq(yieldToken.allowance(address(yieldModule), address(swapProvider)), 0);
        assertEq(yieldToken.balanceOf(address(yieldModule)), 0);
        assertEq(outToken.balanceOf(otherAccount) - receiverBalanceBefore, amountOut);
    }

    function test_swapAndReceive_DepositsTokenOutToProtocolWhenActiveAndFeeIsZero() public {
        TestERC20 outToken = _deployTestToken();

        vm.prank(owner);
        yieldModule.initYieldToken(address(outToken), 0);

        uint amountIn = 1_000e6;
        uint amountOut = 500e6;

        _mintYieldToken(owner, amountIn);
        _mintToken(outToken, address(swapProvider), amountOut);

        bytes memory data = _swapExactInData(address(outToken), amountIn, amountOut);

        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(outToken), amountOut, address(yieldModule), 0);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.LatestFeePaymentStateUpdated(
            address(outToken),
            amountOut,
            SERVICE_FEE_RATE
        );
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapAndReceiveCompleted(address(outToken), otherAccount, amountOut, true);

        _swapAndReceive(address(outToken), otherAccount, amountIn, data);
    }

    function test_swapAndReceive_DepositsTokenOutAndProcessesServiceFeeWhenActiveAndRevenueExists()
        public
    {
        TestERC20 outToken = _deployTestToken();

        vm.prank(owner);
        yieldModule.initYieldToken(address(outToken), 0);

        uint seed = 100_000e6;
        _mintToken(outToken, owner, seed);
        vm.startPrank(owner);
        outToken.approve(address(yieldModule), type(uint).max);
        yieldModule.enterProtocolByOwner(address(outToken));
        vm.stopPrank();

        uint accumulatedRevenue = 10_000e6;
        _generateRevenue(address(yieldModule), accumulatedRevenue);
        uint expectedFeeOut = accumulatedRevenue * SERVICE_FEE_RATE / PRECISION;

        uint amountIn = 1_000e6;
        uint amountOut = 500e6;

        _mintYieldToken(owner, amountIn);
        _mintToken(outToken, address(swapProvider), amountOut);

        bytes memory data = _swapExactInData(address(outToken), amountIn, amountOut);

        vm.expectEmit(address(pool));
        emit AaveV3PoolMock.Supply(address(outToken), amountOut, address(yieldModule), 0);
        vm.expectEmit(address(protocolToken));
        emit IERC20.Transfer(address(yieldModule), feeReceiver, expectedFeeOut);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.FeePaymentProcessed(address(outToken), expectedFeeOut, feeReceiver);
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.SwapAndReceiveCompleted(address(outToken), otherAccount, amountOut, true);

        _swapAndReceive(address(outToken), otherAccount, amountIn, data);
    }
}
