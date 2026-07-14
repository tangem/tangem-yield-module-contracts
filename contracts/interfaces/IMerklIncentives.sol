// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IMerklIncentives {
    error DuplicateRewardToken(address rewardToken);
    error MerklClaimedNoReward(address rewardToken, address finalRecipient);
    error RewardTokensEmpty();
    error RewardTokensLengthsMismatch();
    error YieldTokenNotSet(address yieldToken);

    event MerklClaimed(
        address indexed distributor,
        address indexed rewardToken,
        uint256 received,
        address finalRecipient,
        address finalToken,
        uint256 finalAmount,
        address indexed caller
    );

    function claimMerklRewardsOwner(
        address distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;

    function claimMerklRewardsBE(
        address distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;
}
