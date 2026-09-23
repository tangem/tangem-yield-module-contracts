// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { PRECISION } from "contracts/common/Constants.sol";
import { Requires } from "contracts/common/Requires.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";

import { MerklIncentivesFixture, TestERC20 } from "./MerklIncentivesFixture.sol";

contract MerklServiceFeeTest is MerklIncentivesFixture {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /* fee is charged on the received delta, never on the cumulative amount */

    function test_claim_ChargesFeeOnNewlyReceivedDeltaOnly() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        uint feeAfterFirstClaim = rewardToken.balanceOf(feeReceiver);
        assertEq(feeAfterFirstClaim, _expectedRewardFee(AMOUNT));

        // the same cumulative amount plus a top-up: only the delta is charged
        uint topUp = AMOUNT / 4;
        _fundMerklDistributor(address(rewardToken), topUp);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            address(rewardToken),
            topUp,
            _expectedRewardFee(topUp),
            owner,
            address(rewardToken),
            topUp - _expectedRewardFee(topUp),
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT + topUp);

        assertEq(rewardToken.balanceOf(feeReceiver), feeAfterFirstClaim + _expectedRewardFee(topUp));
    }

    /* rounding */

    function test_claim_ChargesNoFee_WhenRewardIsDust() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), 1);

        // the fee rounds to zero, so nothing is transferred and the event reports a zero fee amount
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            address(rewardToken),
            1,
            0,
            owner,
            address(rewardToken),
            1,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), 1);

        // 1 * 100 / 10000 rounds down to zero, so the owner keeps the whole dust
        assertEq(rewardToken.balanceOf(feeReceiver), 0);
        assertEq(rewardToken.balanceOf(owner), 1);
    }

    /* fee receiver comes from the processor only */

    function test_claim_Reverts_WhenFeeReceiverIsZero() public {
        vm.prank(backend);
        processor.setFeeReceiver(address(0));

        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectRevert(Requires.ZeroAddress.selector);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_Reverts_WhenFeeReceiverIsZeroAndRateIsZero() public {
        vm.prank(backend);
        processor.setFeeReceiver(address(0));
        _setServiceFeeRate(0);

        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        // the receiver is validated once per claim, before the rate is applied, so a zero rate is no exception
        vm.expectRevert(Requires.ZeroAddress.selector);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_SendsFeeToUpdatedFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        vm.prank(backend);
        processor.setFeeReceiver(newFeeReceiver);

        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        // the receiver is read from the processor at execution time
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            address(rewardToken),
            AMOUNT,
            fee,
            owner,
            address(rewardToken),
            AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(newFeeReceiver), fee);
        assertEq(rewardToken.balanceOf(feeReceiver), 0);
    }

    /* atomicity: a failed fee transfer reverts the whole claim */

    function test_claim_Reverts_WhenFeeTransferFails() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        // the reward reached the module, but the fee receiver cannot be paid in this token
        rewardToken.blacklist(feeReceiver);

        vm.expectRevert(abi.encodeWithSelector(TestERC20.AccountIsBlacklisted.selector, feeReceiver));

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    /* the reward fee is settled at claim time, so it is not charged again later */

    function test_claim_ThenCollectServiceFee_DoesNotChargeRewardTwice() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        uint rewardFee = _expectedRewardFee(YIELD_AMOUNT);
        assertEq(yieldToken.balanceOf(feeReceiver), rewardFee);

        // only the fee accrued on the yield growth is left to collect
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);

        _collectViaProcessor(ym);

        assertEq(protocolToken.balanceOf(feeReceiver), ACCUMULATED_SERVICE_FEE);
        assertEq(ym.calculateServiceFee(address(yieldToken)), 0);
    }

    /* launch rate: 15% pinned as a literal, independent of the fee helpers */

    function test_claim_ChargesLaunchRate_OnUnknownToken() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE);

        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(feeReceiver), _launchRateFee(AMOUNT));
        assertEq(rewardToken.balanceOf(owner), AMOUNT - _launchRateFee(AMOUNT));
    }

    /* fee-on-transfer reward tokens */

    function test_claim_ChargesFeeOnCreditedAmount_WhenActiveUnderlyingHasTransferTax() public {
        uint tax = YIELD_AMOUNT / 1000;

        yieldToken.setFixedTax(tax);
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        // the module was credited one tax less, and the fee follows that delta
        uint received = YIELD_AMOUNT - tax;
        uint fee = _expectedRewardFee(received);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        // the fee transfer and the supply are each taxed once more, but the module keeps nothing back
        assertEq(yieldToken.balanceOf(feeReceiver), fee - tax);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + received - fee - tax);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
    }

    /* no fee debt is created on any route */

    function test_claim_CreatesNoFeeDebt_OnAnyRoute() public {
        TestERC20 unknownToken = _createRewardToken();

        _fundMerklDistributor(address(unknownToken), AMOUNT);
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(3);
        rewardTokens[0] = address(unknownToken);
        rewardTokens[1] = address(yieldToken);
        rewardTokens[2] = address(protocolToken);
        cumulativeAmounts[0] = AMOUNT;
        cumulativeAmounts[1] = YIELD_AMOUNT;
        cumulativeAmounts[2] = YIELD_AMOUNT;

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, rewardTokens, cumulativeAmounts, proofs);

        assertEq(ym.feeDebts(address(unknownToken)), 0);
        assertEq(ym.feeDebts(address(yieldToken)), 0);
        assertEq(ym.feeDebts(address(protocolToken)), 0);
    }

    /* each token in a batch is charged on its own amount */

    function testFuzz_claim_ChargesEachTokenIndependently(uint firstAmount, uint secondAmount) public {
        firstAmount = bound(firstAmount, 1, type(uint128).max);
        secondAmount = bound(secondAmount, 1, type(uint128).max);

        TestERC20[] memory tokens = _createRewardTokens(2);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(2);
        rewardTokens[0] = address(tokens[0]);
        rewardTokens[1] = address(tokens[1]);
        cumulativeAmounts[0] = firstAmount;
        cumulativeAmounts[1] = secondAmount;

        _fundMerklDistributor(rewardTokens[0], firstAmount);
        _fundMerklDistributor(rewardTokens[1], secondAmount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, rewardTokens, cumulativeAmounts, proofs);

        // rounding is applied per token, so the total can differ from a fee on the summed amount
        assertEq(tokens[0].balanceOf(feeReceiver), _expectedRewardFee(firstAmount));
        assertEq(tokens[1].balanceOf(feeReceiver), _expectedRewardFee(secondAmount));
    }

    /* invariant: gross splits into fee plus net on every route */

    function testFuzz_claim_SplitsGrossIntoFeeAndNet_OnUnknownToken(uint amount, uint rate) public {
        amount = bound(amount, 1, type(uint128).max);
        rate = bound(rate, 0, CLAIM_MAX_SERVICE_FEE_RATE);

        _setServiceFeeRate(rate);

        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), amount);

        uint fee = amount * rate / PRECISION;

        // the fee field reports exactly what leaves the module under the applied rate
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            address(rewardToken),
            amount,
            fee,
            owner,
            address(rewardToken),
            amount - fee,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), amount);

        assertEq(rewardToken.balanceOf(feeReceiver) + rewardToken.balanceOf(owner), amount);
        assertEq(rewardToken.balanceOf(feeReceiver), fee);
    }

    function testFuzz_claim_SplitsGrossIntoFeeAndNet_OnActiveUnderlying(uint amount, uint rate) public {
        amount = bound(amount, 1, type(uint128).max);
        rate = bound(rate, 0, CLAIM_MAX_SERVICE_FEE_RATE);

        _setServiceFeeRate(rate);

        _fundMerklDistributor(address(yieldToken), amount);

        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _claimSingleAsOwner(address(yieldToken), amount);

        // the fee is withheld in the underlying while the net amount is supplied to the protocol
        uint fee = yieldToken.balanceOf(feeReceiver);
        uint netAmount = ym.protocolBalance(address(yieldToken)) - protocolBalanceBefore;

        assertEq(fee, amount * rate / PRECISION);
        assertEq(fee + netAmount, amount);
    }

    function testFuzz_claim_SplitsGrossIntoFeeAndNet_OnActiveProtocolToken(uint amount, uint rate) public {
        amount = bound(amount, 1, type(uint128).max);
        rate = bound(rate, 0, CLAIM_MAX_SERVICE_FEE_RATE);

        _setServiceFeeRate(rate);

        _fundMerklDistributor(address(protocolToken), amount);

        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _claimSingleAsOwner(address(protocolToken), amount);

        uint fee = protocolToken.balanceOf(feeReceiver);
        uint netAmount = ym.protocolBalance(address(yieldToken)) - protocolBalanceBefore;

        assertEq(fee, amount * rate / PRECISION);
        assertEq(fee + netAmount, amount);
    }

    function testFuzz_claim_SplitsGrossIntoFeeAndNet_OnInactiveProtocolToken(uint amount, uint rate) public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        rate = bound(rate, 0, CLAIM_MAX_SERVICE_FEE_RATE);
        _setServiceFeeRate(rate);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint feeReceiverBalanceBefore = protocolToken.balanceOf(feeReceiver);

        // unwrap pays the underlying out of the pool, so it is capped by pool liquidity
        amount = bound(amount, 1, poolBalanceBefore);

        _fundMerklDistributor(address(protocolToken), amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        // the fee stays in the aToken while the net amount reaches the owner as the underlying
        uint fee = protocolToken.balanceOf(feeReceiver) - feeReceiverBalanceBefore;
        uint unwrapped = yieldToken.balanceOf(owner) - ownerBalanceBefore;

        assertEq(fee, amount * rate / PRECISION);
        assertEq(fee + unwrapped, amount);
    }

    /* helpers */

    function _launchRateFee(uint received) internal pure returns (uint) {
        return received * CLAIM_MAX_SERVICE_FEE_RATE / PRECISION;
    }
}
