// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMerklIncentives} from "../interfaces/IMerklIncentives.sol";
import {IMerklDistributor} from "../interfaces/IMerklDistributor.sol";
import {IMerklDistributorsRegistry} from "../interfaces/IMerklDistributorsRegistry.sol";

import {Requires} from "../common/Requires.sol";
import {YieldModuleLiquidUpgradeable} from "../core/YieldModuleLiquidUpgradeable.sol";

abstract contract MerklIncentives is IMerklIncentives, YieldModuleLiquidUpgradeable {
    using Requires for uint256;
    using Requires for address;

    IMerklDistributorsRegistry public immutable distributorRegistry;

    enum TokenAction {
        PUSH_TO_PROTOCOL,
        PULL_TO_OWNER,
        SEND_TO_OWNER,
        LEAVE_IN_POOL
    }

    constructor(address distributorRegistry_) {
        distributorRegistry = IMerklDistributorsRegistry(distributorRegistry_);
    }

    function claimMerklRewardsOwner(
        address distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyOwner nonReentrant {
        _claimMerklRewards(distributor, rewardTokens, cumulativeAmounts, proofs, owner);
    }

    function claimMerklRewardsBE(
        address distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyProcessor nonReentrant {
        _claimMerklRewards(distributor, rewardTokens, cumulativeAmounts, proofs, address(processor));
    }

    function _claimMerklRewards(
        address distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs,
        address caller
    ) private {
        require(
            distributorRegistry.allowedMerklDistributors(distributor),
            IMerklDistributorsRegistry.DistributorNotAllowed(distributor)
        );
        require(rewardTokens.length > 0, RewardTokensEmpty());
        require(
            rewardTokens.length == cumulativeAmounts.length
                && cumulativeAmounts.length == proofs.length,
            RewardTokensLengthsMismatch()
        );

        _validateRewardTokens(rewardTokens);

        uint256[] memory balancesBefore = new uint256[](rewardTokens.length);
        address[] memory users = new address[](rewardTokens.length);
        address[] memory recipients = new address[](rewardTokens.length);
        TokenAction[] memory actions = new TokenAction[](rewardTokens.length);
        bytes[] memory emptyDatas = new bytes[](rewardTokens.length);

        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            (address finalRecipient, TokenAction action) =
                _routeRewardsByTokenPolicy(rewardTokens[i]);

            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(finalRecipient);
            users[i] = address(this);
            recipients[i] = finalRecipient;
            actions[i] = action;
        }

        IMerklDistributor(distributor)
            .claimWithRecipient(
                users, rewardTokens, cumulativeAmounts, proofs, recipients, emptyDatas
            );

        _processClaimedRewards(
            distributor, rewardTokens, recipients, actions, balancesBefore, caller
        );
    }

    function _processClaimedRewards(
        address distributor,
        address[] calldata rewardTokens,
        address[] memory recipients,
        TokenAction[] memory actions,
        uint256[] memory balancesBefore,
        address caller
    ) private {
        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 balanceAfter = IERC20(rewardTokens[i]).balanceOf(recipients[i]);
            uint256 received =
                balanceAfter > balancesBefore[i] ? (balanceAfter - balancesBefore[i]) : 0;
            require(received > 0, MerklClaimedNoReward(rewardTokens[i], recipients[i]));

            address finalToken = rewardTokens[i];
            uint256 finalAmount = received;
            address finalRecipient = recipients[i];

            if (actions[i] == TokenAction.PUSH_TO_PROTOCOL) {
                uint256 protocolBalanceBefore = _protocolBalance(rewardTokens[i]);
                _pushToProtocol(rewardTokens[i], received);

                uint256 protocolBalanceAfter = _protocolBalance(rewardTokens[i]);
                require(
                    protocolBalanceAfter > protocolBalanceBefore,
                    MerklClaimedNoReward(rewardTokens[i], address(this))
                );

                finalToken = address(protocolTokens[rewardTokens[i]]);
                finalAmount = protocolBalanceAfter - protocolBalanceBefore;

                _increaseProtocolBalanceWithoutFee(rewardTokens[i], finalAmount);
            } else if (actions[i] == TokenAction.PULL_TO_OWNER) {
                finalToken = yieldTokenByProtocolToken[rewardTokens[i]];
                finalAmount = _pullFromProtocolToOwner(finalToken, type(uint256).max);
                finalRecipient = owner;
            } else if (actions[i] == TokenAction.LEAVE_IN_POOL) {
                address yieldToken = yieldTokenByProtocolToken[rewardTokens[i]];
                _increaseProtocolBalanceWithoutFee(yieldToken, received);
            }

            emit MerklClaimed(
                distributor,
                rewardTokens[i],
                received,
                finalRecipient,
                finalToken,
                finalAmount,
                caller
            );
        }
    }

    function _routeRewardsByTokenPolicy(address rewardToken)
        private
        returns (address finalRecipient, TokenAction action)
    {
        if (isProtocolToken[rewardToken]) {
            // i.e aUSDC
            address yieldToken = _getYieldToken(rewardToken); // i.e. USDC (underlying)

            if (yieldTokensData[yieldToken].active) {
                // active USDC (underlying)
                return (address(this), TokenAction.LEAVE_IN_POOL);
            } else {
                // i.e. inactive USDC (underlying)
                return (address(this), TokenAction.PULL_TO_OWNER);
            }
        } else if (yieldTokensData[rewardToken].active) {
            // i.e. active USDC (underlying)
            return (address(this), TokenAction.PUSH_TO_PROTOCOL);
        } else {
            return (owner, TokenAction.SEND_TO_OWNER); // i.e. inactive USDC or other tokens (never initialized in module)
        }
    }

    function _validateRewardTokens(address[] calldata rewardTokens) private pure {
        for (uint256 i; i < rewardTokens.length; ++i) {
            for (uint256 k = i + 1; k < rewardTokens.length; ++k) {
                require(rewardTokens[i] != rewardTokens[k], DuplicateRewardToken(rewardTokens[i]));
            }
        }
    }
}
