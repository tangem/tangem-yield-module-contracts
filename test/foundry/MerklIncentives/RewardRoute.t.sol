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

    /* SEND_TO_OWNER — reward token is unknown to the module */

    function test_claim_SendsToOwner_WhenRewardTokenIsUnknown() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
        assertEq(rewardToken.balanceOf(address(merklDistributor)), 0);
    }

    function test_claim_SendsToOwner_EmitsMerklClaimed() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(address(ym));
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
            cumulativeAmounts[i] = bound(rawAmounts[i], 1, 1_000_000_000e18);
            _fundMerklDistributor(rewardTokens[i], cumulativeAmounts[i]);
        }

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        // every unknown token is routed to the owner in full
        for (uint i; i < numTokens; ++i) {
            assertEq(tokens[i].balanceOf(owner), cumulativeAmounts[i]);
            assertEq(tokens[i].balanceOf(address(ym)), 0);
            assertEq(tokens[i].balanceOf(address(merklDistributor)), 0);
        }
    }

    /* PUSH_TO_PROTOCOL — reward token is an active yield token */

    function test_claim_PushesToProtocol_WhenRewardTokenIsActiveYieldToken() public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(yieldToken), AMOUNT);

        _claimSingleAsOwner(address(yieldToken), AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + AMOUNT);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + AMOUNT);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    function test_claim_PushesToProtocol_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(yieldToken), AMOUNT);

        // the reward becomes a protocol position: finalToken is the aToken, kept by the module
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(yieldToken),
            AMOUNT,
            address(ym),
            address(protocolToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(yieldToken), AMOUNT);
    }

    function test_claim_Reverts_WhenProtocolDepositFailed() public {
        _fundMerklDistributor(address(yieldToken), AMOUNT);

        // tax equal to the full mint amount makes the aToken mint credit nothing,
        // so the supply has zero effect on the protocol balance
        protocolToken.setFixedTax(AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.ProtocolDepositFailed.selector, address(yieldToken)
            )
        );

        _claimSingleAsOwner(address(yieldToken), AMOUNT);
    }

    /* KEEP_IN_MODULE — reward token is a protocol token of an active yield token */

    function test_claim_KeepsInModule_WhenRewardTokenIsProtocolTokenOfActiveYieldToken() public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), AMOUNT);

        _claimSingleAsOwner(address(protocolToken), AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + AMOUNT);
        assertEq(protocolToken.balanceOf(address(ym)), PROTOCOL_BALANCE + AMOUNT);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    function test_claim_KeepsInModule_EmitsMerklClaimed() public {
        _fundMerklDistributor(address(protocolToken), AMOUNT);

        // the aToken reward stays as-is on the module: final fields mirror the claim
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(protocolToken),
            AMOUNT,
            address(ym),
            address(protocolToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), AMOUNT);
    }

    /* UNWRAP_TO_OWNER — reward token is a protocol token of an inactive yield token */

    function test_claim_UnwrapsToOwner_WhenYieldTokenIsInactive() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), AMOUNT);

        _claimSingleAsOwner(address(protocolToken), AMOUNT);

        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + AMOUNT);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore - AMOUNT);
    }

    function test_claim_UnwrapsToOwner_ConsumesClaimedProtocolToken() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        _fundMerklDistributor(address(protocolToken), AMOUNT);
        uint yieldTokenBefore = yieldToken.balanceOf(owner);

        _claimSingleAsOwner(address(protocolToken), AMOUNT);

        assertEq(protocolToken.balanceOf(address(merklDistributor)), 0);
        assertEq(protocolToken.balanceOf(address(ym)), 0);
        assertEq(protocolToken.balanceOf(owner), 0);
        assertEq(yieldToken.balanceOf(owner), yieldTokenBefore + AMOUNT);
    }

    function test_claim_UnwrapsToOwner_EmitsMerklClaimed() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        _fundMerklDistributor(address(protocolToken), AMOUNT);

        // the aToken reward is unwrapped: the owner receives the underlying yieldToken
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(protocolToken),
            AMOUNT,
            owner,
            address(yieldToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(protocolToken), AMOUNT);
    }

    /* Post-claim errors */

    function test_claim_Reverts_WhenDistributorPaysNothing() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        // repeat the claim with the same cumulative amount: the distributor pays the delta
        // over what was already claimed, i.e. nothing
        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.MerklClaimedNoReward.selector, address(rewardToken), owner
            )
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    /* Mixed routes — multiple reward tokens in one claim */

    function test_claim_RoutesEachToken_WhenMixedRoutes() public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        // distinct amounts per route to catch any cross-wiring between them
        uint sendAmount = AMOUNT;
        uint pushAmount = 2 * AMOUNT;
        uint keepAmount = 3 * AMOUNT;

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

        // SEND_TO_OWNER: the unknown token went straight to the owner
        assertEq(unknownToken.balanceOf(owner), sendAmount);
        assertEq(unknownToken.balanceOf(address(ym)), 0);

        // PUSH_TO_PROTOCOL: the yieldToken reward was supplied to the pool
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + pushAmount);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);

        // KEEP_IN_MODULE: the aToken reward stayed on the module; together with the
        // supplied reward the position grew by both amounts
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + pushAmount + keepAmount);
        assertEq(protocolToken.balanceOf(owner), 0);

        // rewards are fee-free regardless of the route
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }
}
