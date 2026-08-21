// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IMerklIncentives {
    error MerklClaimedNoReward(address rewardToken);
    error RewardTokensEmpty();
    error RewardTokensLengthsMismatch();
    error RewardTokensNotSorted(address rewardToken);

    event MerklClaimed(
        address indexed rewardToken,
        uint receivedAmount,
        uint serviceFee,
        address finalRecipient,
        address finalToken,
        uint finalAmount,
        address indexed caller
    );

    function claimMerklRewardsOwner(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;
}
