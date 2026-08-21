// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MerklIncentivesFixture, TestERC20 } from "./MerklIncentivesFixture.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { IMerklDistributor } from "contracts/interfaces/external/IMerklDistributor.sol";

/// Reward routing tests: how claimed Merkl rewards are classified and processed
contract RewardRouteTest is MerklIncentivesFixture {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /* Claim always names the module as both user and recipient */

    function test_claim_PassesModuleAsUserAndRecipient() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(address(rewardToken), AMOUNT);

        address[] memory expectedModule = new address[](1);
        expectedModule[0] = address(ym);

        vm.expectCall(
            address(merklDistributor),
            abi.encodeCall(
                IMerklDistributor.claimWithRecipient,
                (expectedModule, tokens, amounts, proofs, expectedModule, new bytes[](1))
            )
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(address(ym)), 0);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - _expectedRewardFee(AMOUNT));
    }

    /* SEND_TO_OWNER */

    function test_claim_SendsToOwner_ForwardsThroughModule() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        vm.expectEmit(address(rewardToken));
        emit IERC20.Transfer(address(merklDistributor), address(ym), AMOUNT);
        vm.expectEmit(address(rewardToken));
        emit IERC20.Transfer(address(ym), feeReceiver, fee);
        vm.expectEmit(address(rewardToken));
        emit IERC20.Transfer(address(ym), owner, AMOUNT - fee);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_SendsToOwner_EmitsMerklClaimed() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            AMOUNT,
            fee,
            owner,
            address(rewardToken),
            AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_SendsToOwner_UsesReceivedDelta_WhenRewardTokenHasTransferTax() public {
        // the tax is a flat per-transfer amount, so keep it well below the fee to avoid an underflow
        uint tax = AMOUNT / 1000;

        TestERC20 rewardToken = _createRewardToken();
        rewardToken.setFixedTax(tax);
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        // the module was credited less than the cumulative amount, and the fee follows that delta
        uint received = AMOUNT - tax;
        uint fee = _expectedRewardFee(received);

        // every field follows the credited delta, not the cumulative amount
        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            received,
            fee,
            owner,
            address(rewardToken),
            received - fee,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        // each outgoing transfer is taxed as well, so both the fee receiver and the owner get one tax less
        assertEq(rewardToken.balanceOf(feeReceiver), fee - tax);
        assertEq(rewardToken.balanceOf(owner), received - fee - tax);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    function test_claim_SendsToOwner_WhenYieldTokenIsDeactivated() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + YIELD_AMOUNT - fee);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore);
    }

    function test_claim_SendsToOwner_WhenYieldTokenIsEntrySuspended() public {
        _suspendViaProcessor(ym);

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        // supplying is an entry, so a suspended token is forwarded instead of pushed
        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(yieldToken),
            YIELD_AMOUNT,
            fee,
            owner,
            address(yieldToken),
            YIELD_AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        // nothing reached the suspended pool and the accounted position is untouched
        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + YIELD_AMOUNT - fee);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    function testFuzz_claim_SendsToOwner_ManyUnknownTokens(uint numTokens, uint[10] memory rawAmounts) public {
        numTokens = bound(numTokens, 1, 10);

        TestERC20[] memory tokens = _createRewardTokens(numTokens);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) =
            _claimArgs(numTokens);

        for (uint i; i < numTokens; ++i) {
            rewardTokens[i] = address(tokens[i]);
            cumulativeAmounts[i] = bound(rawAmounts[i], 1, type(uint128).max);
            _fundMerklDistributor(rewardTokens[i], cumulativeAmounts[i]);
        }

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        for (uint i; i < numTokens; ++i) {
            uint fee = _expectedRewardFee(cumulativeAmounts[i]);

            assertEq(tokens[i].balanceOf(owner), cumulativeAmounts[i] - fee);
            assertEq(tokens[i].balanceOf(feeReceiver), fee);
            assertEq(tokens[i].balanceOf(address(ym)), 0);
            assertEq(tokens[i].balanceOf(address(merklDistributor)), 0);
            assertEq(merklDistributor.claimed(address(ym), rewardTokens[i]), cumulativeAmounts[i]);
        }
    }

    /* PUSH_TO_PROTOCOL */

    function testFuzz_claim_PushesToProtocol_WhenRewardTokenIsActiveYieldToken(uint amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(yieldToken), amount);

        uint fee = _expectedRewardFee(amount);

        _claimSingleAsOwner(address(yieldToken), amount);

        // the fee is taken in the received token — the underlying — before the rest is supplied
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount - fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + amount - fee);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);

        // the reward moved the checkpoint with it, so the pre-claim accrual is all that is owed
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
        assertEq(merklDistributor.claimed(address(ym), address(yieldToken)), amount);
    }

    function test_claim_PushesToProtocol_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        // the reward becomes a protocol position: finalToken is the aToken, kept by the module
        // the fee is withheld in the received underlying, before the net amount is supplied
        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(yieldToken),
            YIELD_AMOUNT,
            fee,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);
    }

    function test_claim_PushesToProtocol_AfterEntryResumed() public {
        _suspendViaProcessor(ym);
        _resumeViaProcessor(ym);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + YIELD_AMOUNT - fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + YIELD_AMOUNT - fee);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    /* KEEP_IN_MODULE */

    function testFuzz_claim_KeepsInModule_WhenRewardTokenIsProtocolTokenOfActiveYieldToken(uint amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), amount);

        uint fee = _expectedRewardFee(amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        // the reward is already the protocol token, so the fee leaves in the aToken itself
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount - fee);
        assertEq(protocolToken.balanceOf(address(ym)), PROTOCOL_BALANCE + amount - fee);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
        assertEq(merklDistributor.claimed(address(ym), address(protocolToken)), amount);
    }

    function test_claim_KeepsInModule_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        // the aToken reward stays as-is on the module: final fields mirror the claim
        // and the fee leaves in the aToken itself
        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(protocolToken),
            YIELD_AMOUNT,
            fee,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    function test_claim_KeepsInModule_WhenYieldTokenIsEntrySuspended() public {
        _suspendViaProcessor(ym);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(protocolToken),
            YIELD_AMOUNT,
            fee,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + YIELD_AMOUNT - fee);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    /* UNWRAP_TO_OWNER  */

    function testFuzz_claim_UnwrapsToOwner_WhenYieldTokenIsInactive(uint amount) public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        // deactivation already paid the accrued fee in aToken, so measure the delta from here
        uint feeReceiverBalanceBefore = protocolToken.balanceOf(feeReceiver);

        // unwrap pays the underlying out of the pool, so it is capped by pool liquidity
        amount = bound(amount, 1, poolBalanceBefore);

        _fundMerklDistributor(address(protocolToken), amount);

        uint fee = _expectedRewardFee(amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        // the fee is kept in the aToken; only the net amount is unwrapped for the owner
        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + amount - fee);
        assertEq(protocolToken.balanceOf(feeReceiver), feeReceiverBalanceBefore + fee);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore - (amount - fee));
        assertEq(merklDistributor.claimed(address(ym), address(protocolToken)), amount);

        // the claimed aToken is fully consumed: the owner never holds it and nothing is stranded
        assertEq(protocolToken.balanceOf(address(ym)), 0);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(protocolToken.balanceOf(address(merklDistributor)), 0);
    }

    function test_claim_UnwrapsToOwner_EmitsMerklClaimed() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);

        // the aToken reward is unwrapped: the owner receives the underlying yieldToken,
        // while the fee stays in the aToken
        vm.expectEmit(true, true, false, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(protocolToken),
            YIELD_AMOUNT,
            fee,
            owner,
            address(yieldToken),
            YIELD_AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    /* Post-claim errors */

    /// the received-delta check runs before any routing, so one route covers every reward class
    function test_claim_Reverts_WhenDistributorPaysNothing() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.MerklClaimedNoReward.selector, address(rewardToken)));

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    /* Mixed routes — multiple reward tokens in one claim */

    function testFuzz_claim_RoutesEachToken_WhenMixedRoutes(uint sendAmount, uint pushAmount, uint keepAmount) public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        sendAmount = bound(sendAmount, 1, type(uint128).max);
        pushAmount = bound(pushAmount, 1, type(uint128).max);
        keepAmount = bound(keepAmount, 1, type(uint128).max);

        TestERC20 unknownToken = _createRewardToken();
        _fundMerklDistributor(address(unknownToken), sendAmount);
        _fundMerklDistributor(address(yieldToken), pushAmount);
        _fundMerklDistributor(address(protocolToken), keepAmount);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(3);
        rewardTokens[0] = address(unknownToken);
        rewardTokens[1] = address(yieldToken);
        rewardTokens[2] = address(protocolToken);
        cumulativeAmounts[0] = sendAmount;
        cumulativeAmounts[1] = pushAmount;
        cumulativeAmounts[2] = keepAmount;

        uint sendNet = sendAmount - _expectedRewardFee(sendAmount);
        uint pushNet = pushAmount - _expectedRewardFee(pushAmount);
        uint keepNet = keepAmount - _expectedRewardFee(keepAmount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        // SEND_TO_OWNER:
        assertEq(unknownToken.balanceOf(owner), sendNet);
        assertEq(unknownToken.balanceOf(feeReceiver), sendAmount - sendNet);
        assertEq(unknownToken.balanceOf(address(ym)), 0);

        // PUSH_TO_PROTOCOL:
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + pushNet);
        assertEq(yieldToken.balanceOf(feeReceiver), pushAmount - pushNet);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);

        // KEEP_IN_MODULE:
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + pushNet + keepNet);
        assertEq(protocolToken.balanceOf(feeReceiver), keepAmount - keepNet);
        assertEq(protocolToken.balanceOf(owner), 0);

        // each token is charged independently, and no route lets a reward be charged twice
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    /// PUSH_TO_PROTOCOL supplies the underlying, which mints the very aToken that
    /// KEEP_IN_MODULE was measured on, so the pair must settle the same in either order
    function testFuzz_claim_SettlesActivePairIndependently_InEitherOrder(bool underlyingFirst) public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(2);
        rewardTokens[0] = underlyingFirst ? address(yieldToken) : address(protocolToken);
        rewardTokens[1] = underlyingFirst ? address(protocolToken) : address(yieldToken);
        cumulativeAmounts[0] = YIELD_AMOUNT;
        cumulativeAmounts[1] = YIELD_AMOUNT;

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        // both rewards land in the position, each charged once on its own delta: the aToken
        // minted by the push is never counted as part of the aToken reward
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + 2 * net);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    /// UNWRAP_TO_OWNER pays the owner in the same token SEND_TO_OWNER forwards,
    /// so both credits must reach the owner in full in either order
    function testFuzz_claim_SettlesInactivePairIndependently_InEitherOrder(bool underlyingFirst) public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        // deactivation already paid the accrued fee in aToken, so measure the delta from here
        uint feeReceiverProtocolBefore = protocolToken.balanceOf(feeReceiver);

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(2);
        rewardTokens[0] = underlyingFirst ? address(yieldToken) : address(protocolToken);
        rewardTokens[1] = underlyingFirst ? address(protocolToken) : address(yieldToken);
        cumulativeAmounts[0] = YIELD_AMOUNT;
        cumulativeAmounts[1] = YIELD_AMOUNT;

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        // the unwrapped reward and the forwarded one both credit the owner, and each fee
        // is withheld in the token it was received in
        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + 2 * net);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(protocolToken.balanceOf(feeReceiver), feeReceiverProtocolBefore + fee);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(protocolToken.balanceOf(address(ym)), 0);
        assertEq(ym.protocolBalance(address(yieldToken)), 0);
    }

    /* Withdrawal pre-claim flow */

    function test_WithdrawalPreClaim_TransfersEverythingToOwner() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);
        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        uint rewardFee = _expectedRewardFee(YIELD_AMOUNT);

        uint protocolBalance = ym.protocolBalance(address(yieldToken));
        uint fee = ym.calculateServiceFee(address(yieldToken));
        assertEq(protocolBalance, PROTOCOL_BALANCE + YIELD_AMOUNT - rewardFee);

        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        // the reward fee was already taken at claim time in the underlying, so the withdrawal
        // only settles the fee accrued on the yield growth
        assertEq(yieldToken.balanceOf(owner), protocolBalance - fee);
        assertEq(yieldToken.balanceOf(feeReceiver), rewardFee);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(ym.protocolBalance(address(yieldToken)), 0);

        (, bool active,) = ym.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }
}
