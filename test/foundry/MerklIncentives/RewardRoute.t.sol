// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { MerklIncentivesBase, TestERC20 } from "./MerklIncentivesBase.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";

/// Reward routing tests: how claimed Merkl rewards are classified and processed
contract RewardRouteTest is MerklIncentivesBase {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /* SEND_TO_OWNER */

    function test_claim_SendsToOwner_WhenRewardTokenIsUnknown() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
        assertEq(rewardToken.balanceOf(address(merklDistributor)), 0);
        assertEq(merklDistributor.claimed(address(ym), address(rewardToken)), AMOUNT);
    }

    function test_claim_SendsToOwner_EmitsMerklClaimed() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(rewardToken),
            AMOUNT,
            owner,
            address(rewardToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_SendsToOwner_UsesReceivedDelta_WhenRewardTokenHasTransferTax() public {
        uint tax = AMOUNT / 10;

        TestERC20 rewardToken = _createRewardToken();
        rewardToken.setFixedTax(tax);
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(rewardToken),
            AMOUNT - tax,
            owner,
            address(rewardToken),
            AMOUNT - tax,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - tax);
    }

    function test_claim_SendsToOwner_WhenYieldTokenIsDeactivated() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + YIELD_AMOUNT);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore);
    }

    function testFuzz_claim_SendsToOwner_ManyUnknownTokens(
        uint numTokens,
        uint[10] memory rawAmounts
    ) public {
        numTokens = bound(numTokens, 1, 10);

        TestERC20[] memory tokens = _createRewardTokens(numTokens);

        address[] memory rewardTokens = new address[](numTokens);
        uint[] memory cumulativeAmounts = new uint[](numTokens);
        bytes32[][] memory proofs = new bytes32[][](numTokens);

        for (uint i; i < numTokens; ++i) {
            rewardTokens[i] = address(tokens[i]);
            cumulativeAmounts[i] = bound(rawAmounts[i], 1, type(uint).max - tokens[i].totalSupply());
            _fundMerklDistributor(rewardTokens[i], cumulativeAmounts[i]);
        }

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        for (uint i; i < numTokens; ++i) {
            assertEq(tokens[i].balanceOf(owner), cumulativeAmounts[i]);
            assertEq(tokens[i].balanceOf(address(ym)), 0);
            assertEq(tokens[i].balanceOf(address(merklDistributor)), 0);
        }
    }

    /* PUSH_TO_PROTOCOL */

    function testFuzz_claim_PushesToProtocol_WhenRewardTokenIsActiveYieldToken(uint amount) public {
        amount = bound(
            amount, 1, type(uint).max - yieldToken.totalSupply() - protocolToken.totalSupply()
        );

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(yieldToken), amount);

        _claimSingleAsOwner(address(yieldToken), amount);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + amount);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);

        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
        assertEq(merklDistributor.claimed(address(ym), address(yieldToken)), amount);
    }

    function test_claim_PushesToProtocol_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        // the reward becomes a protocol position: finalToken is the aToken, kept by the module
        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(yieldToken),
            YIELD_AMOUNT,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);
    }

    function test_claim_Reverts_WhenProtocolDepositFailed() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        // tax equal to the full mint amount makes the aToken mint credit nothing,
        // so the supply has zero effect on the protocol balance
        protocolToken.setFixedTax(YIELD_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.ProtocolDepositFailed.selector, address(yieldToken)
            )
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);
    }

    /* KEEP_IN_MODULE */

    function testFuzz_claim_KeepsInModule_WhenRewardTokenIsProtocolTokenOfActiveYieldToken(uint amount)
        public
    {
        amount = bound(amount, 1, type(uint).max - protocolToken.totalSupply() - PROTOCOL_BALANCE);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount);
        assertEq(protocolToken.balanceOf(address(ym)), PROTOCOL_BALANCE + amount);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
        assertEq(merklDistributor.claimed(address(ym), address(protocolToken)), amount);
    }

    function test_claim_KeepsInModule_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        // the aToken reward stays as-is on the module: final fields mirror the claim
        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(protocolToken),
            YIELD_AMOUNT,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    /* UNWRAP_TO_OWNER  */

    function testFuzz_claim_UnwrapsToOwner_WhenYieldTokenIsInactive(uint amount) public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        // unwrap pays the underlying out of the pool, so it is capped by pool liquidity
        amount = bound(amount, 1, poolBalanceBefore);

        _fundMerklDistributor(address(protocolToken), amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + amount);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore - amount);
        assertEq(merklDistributor.claimed(address(ym), address(protocolToken)), amount);
    }

    function test_claim_UnwrapsToOwner_ConsumesClaimedProtocolToken() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);
        uint yieldTokenBefore = yieldToken.balanceOf(owner);

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);

        assertEq(protocolToken.balanceOf(address(merklDistributor)), 0);
        assertEq(protocolToken.balanceOf(address(ym)), 0);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(yieldToken.balanceOf(owner), yieldTokenBefore + YIELD_AMOUNT);
    }

    function test_claim_UnwrapsToOwner_EmitsMerklClaimed() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        // the aToken reward is unwrapped: the owner receives the underlying yieldToken
        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(protocolToken),
            YIELD_AMOUNT,
            owner,
            address(yieldToken),
            YIELD_AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);
    }

    /* Post-claim errors */

    function test_claim_Reverts_WhenDistributorPaysNothing() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.MerklClaimedNoReward.selector, address(rewardToken), owner
            )
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claim_Reverts_WhenDistributorPaysNothingToModule() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.MerklClaimedNoReward.selector, address(yieldToken), address(ym)
            )
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);
    }

    /* Mixed routes — multiple reward tokens in one claim */

    function testFuzz_claim_RoutesEachToken_WhenMixedRoutes(
        uint sendAmount,
        uint pushAmount,
        uint keepAmount
    ) public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        sendAmount = bound(sendAmount, 1, type(uint).max / 4);
        pushAmount = bound(pushAmount, 1, type(uint).max / 4);
        keepAmount = bound(keepAmount, 1, type(uint).max / 4);

        TestERC20 unknownToken = _createRewardToken();
        _fundMerklDistributor(address(unknownToken), sendAmount);
        _fundMerklDistributor(address(yieldToken), pushAmount);
        _fundMerklDistributor(address(protocolToken), keepAmount);

        address[] memory rewardTokens = new address[](3);
        rewardTokens[0] = address(unknownToken);
        rewardTokens[1] = address(yieldToken);
        rewardTokens[2] = address(protocolToken);

        uint[] memory cumulativeAmounts = new uint[](3);
        cumulativeAmounts[0] = sendAmount;
        cumulativeAmounts[1] = pushAmount;
        cumulativeAmounts[2] = keepAmount;

        bytes32[][] memory proofs = new bytes32[][](3);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        // SEND_TO_OWNER:
        assertEq(unknownToken.balanceOf(owner), sendAmount);
        assertEq(unknownToken.balanceOf(address(ym)), 0);

        // PUSH_TO_PROTOCOL:
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + pushAmount);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);

        // KEEP_IN_MODULE:
        assertEq(
            ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + pushAmount + keepAmount
        );
        assertEq(protocolToken.balanceOf(owner), 0);

        // rewards are fee-free regardless of the route
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    /* Withdrawal pre-claim flow */

    function test_claim_ThenWithdrawAndDeactivate_TransfersEverythingToOwner() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);
        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        uint protocolBalance = ym.protocolBalance(address(yieldToken));
        uint fee = ym.calculateServiceFee(address(yieldToken));
        assertEq(protocolBalance, PROTOCOL_BALANCE + YIELD_AMOUNT);

        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        // the owner exits with principal + revenue + claimed reward minus the service fee
        assertEq(yieldToken.balanceOf(owner), protocolBalance - fee);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(ym.protocolBalance(address(yieldToken)), 0);

        (, bool active,) = ym.yieldTokensData(address(yieldToken));
        assertFalse(active);
    }
}
