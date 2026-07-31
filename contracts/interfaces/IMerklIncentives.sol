// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IMerklIncentives {
    error DuplicateRewardToken(address rewardToken);
    error MerklClaimedNoReward(address rewardToken, address finalRecipient);
    error RewardTokensEmpty();
    error RewardTokensLengthsMismatch();
    error ServiceFeeRateExceedsMax(uint serviceFeeRate);

    event MerklClaimed(
        address indexed distributor,
        address indexed rewardToken,
        uint received,
        address finalRecipient,
        address finalToken,
        uint finalAmount,
        address indexed caller
    );

    function claimMerklRewardsOwner(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs,
        uint maxServiceFeeRate
    ) external;

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs,
        uint maxServiceFeeRate
    ) external;
}
