// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IMerklIncentives {
    error MerklClaimedNoReward(address receivedToken);
    error RewardTokensEmpty();
    error RewardTokensLengthsMismatch();

    event MerklClaimed(
        address indexed rewardToken,
        address indexed receivedToken,
        uint receivedAmount,
        uint serviceFee,
        address finalRecipient,
        address finalToken,
        uint finalAmount,
        address indexed caller
    );

    struct Claim {
        address[] users;
        address[] tokens;
        uint[] amounts;
        bytes32[][] proofs;
        bytes[] datas;
    }

    function claimMerklRewardsOwner(
        address[] calldata rewardTokens,
        address[] calldata receivedTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        address[] calldata receivedTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external;
}
