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

    function test_claim_SendsToOwner_WhenYieldTokenIsDeactivated() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        _fundMerklDistributor(address(yieldToken), AMOUNT);

        _claimSingleAsOwner(address(yieldToken), AMOUNT);

        // a deactivated yieldToken is not pushed back to the protocol — it goes to the owner
        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + AMOUNT);
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

    function testFuzz_claim_PushesToProtocol_WhenRewardTokenIsActiveYieldToken(
        uint amount
    ) public {
        amount = bound(amount, 1, 1_000_000_000e18);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(yieldToken), amount);

        _claimSingleAsOwner(address(yieldToken), amount);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount);
        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + amount);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);
        // the reward itself is fee-free at any size
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
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

    function testFuzz_claim_KeepsInModule_WhenRewardTokenIsProtocolTokenOfActiveYieldToken(
        uint amount
    ) public {
        amount = bound(amount, 1, 1_000_000_000e18);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        _fundMerklDistributor(address(protocolToken), amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + amount);
        assertEq(protocolToken.balanceOf(address(ym)), PROTOCOL_BALANCE + amount);
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

    function test_claim_Reverts_WhenDistributorPaysNothingToModule() public {
        _fundMerklDistributor(address(yieldToken), AMOUNT);

        _claimSingleAsOwner(address(yieldToken), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.MerklClaimedNoReward.selector, address(yieldToken), address(ym)
            )
        );

        _claimSingleAsOwner(address(yieldToken), AMOUNT);
    }

    /* Mixed routes — multiple reward tokens in one claim */

    function testFuzz_claim_RoutesEachToken_WhenMixedRoutes(
        uint sendAmount,
        uint pushAmount,
        uint keepAmount
    ) public {
        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));

        // independent amounts per route to catch any cross-wiring between them
        sendAmount = bound(sendAmount, 1, 1_000_000_000e18);
        pushAmount = bound(pushAmount, 1, 1_000_000_000e18);
        keepAmount = bound(keepAmount, 1, 1_000_000_000e18);

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
