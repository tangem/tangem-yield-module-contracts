// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { MerklIncentivesBase } from "./MerklIncentivesBase.sol";

import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";

contract MerklIncentivesTest is MerklIncentivesBase {
    function setUp() public override {
        super.setUp();
        // TODO: deploy entered module with funded yieldToken
    }

    /* Validation reverts — triggered before distributor.claimWithRecipient, no mock logic needed */

    function test_claimMerklRewardsOwner_RevertsRewardTokensEmpty() public {
        // vm.expectRevert(IMerklIncentives.RewardTokensEmpty.selector);

        vm.prank(owner);

    }

    function test_claimMerklRewardsOwner_RevertsLengthsMismatch() public {
        // vm.expectRevert(IMerklIncentives.RewardTokensLengthsMismatch.selector);
    }

    function test_claimMerklRewardsOwner_RevertsDuplicateRewardToken() public {
        // vm.expectRevert(abi.encodeWithSelector(
        //     IMerklIncentives.DuplicateRewardToken.selector, rewardToken
        // ));
    }

    /* TokenAction scenarios — require MerklDistributorMock to mint rewards (TODO) */

    // test_claimMerklRewards_PushToProtocolWhenYieldTokenActive
    // test_claimMerklRewards_UnwrapToOwnerWhenProtocolTokenInactive
    // test_claimMerklRewards_KeepInModuleWhenProtocolTokenActive
    // test_claimMerklRewards_SendToOwnerWhenUnknownToken

    /* Access control */

    // test_claimMerklRewardsOwner_RevertsOnlyOwner
    // test_claimMerklRewardsBE_RevertsOnlyProcessor
}