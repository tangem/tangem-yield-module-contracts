// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMerklIncentives} from "../interfaces/IMerklIncentives.sol";
import {IMerklDistributor} from "../interfaces/IMerklDistributor.sol";

import {Requires} from "../common/Requires.sol";
import {YieldModuleLiquidUpgradeable} from "../core/YieldModuleLiquidUpgradeable.sol";

abstract contract MerklIncentives is IMerklIncentives, YieldModuleLiquidUpgradeable {
    using Requires for uint256;
    using Requires for address;

    IMerklDistributor public immutable distributor;

    enum TokenAction {
        PUSH_TO_PROTOCOL,
        UNWRAP_TO_OWNER,
        SEND_TO_OWNER,
        KEEP_IN_MODULE
    }

    struct RewardRoute {
        address recipient;
        address yieldToken;
        TokenAction tokenAction;
    }

    constructor(address distributor_) {
        distributor_.requireNotZero();
        distributor = IMerklDistributor(distributor_);
    }

    function claimMerklRewardsOwner(
        address _distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyOwner nonReentrant {
        _claimMerklRewards(_distributor, rewardTokens, cumulativeAmounts, proofs);
    }

    function claimMerklRewardsBE(
        address _distributor,
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyProcessor nonReentrant {
        _claimMerklRewards(_distributor, rewardTokens, cumulativeAmounts, proofs);
    }

    function _claimMerklRewards(
        address _distributor, // TODO: mb remove this parameter?
        address[] calldata rewardTokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) private {
        // TODO: if we remove the distributor parameter, we cat remove this check
        require(
            _distributor == address(distributor),
            DistributorNotAllowed(address(distributor))
        );
        require(rewardTokens.length > 0, RewardTokensEmpty());
        require(
            rewardTokens.length == cumulativeAmounts.length
                && cumulativeAmounts.length == proofs.length,
            RewardTokensLengthsMismatch()
        );

        uint256[] memory balancesBefore = new uint256[](rewardTokens.length);
        address[] memory users = new address[](rewardTokens.length);
        address[] memory recipients = new address[](rewardTokens.length);
        TokenAction[] memory actions = new TokenAction[](rewardTokens.length);
        bytes[] memory emptyDatas = new bytes[](rewardTokens.length);

        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            // Check for duplicate reward tokens
            for(uint256 k; k < i; ++k) {
                require(rewardTokens[k] != rewardTokens[i], DuplicateRewardToken(rewardTokens[i]));
            }

            RewardRoute memory rewardRoute = _classifyReward(rewardTokens[i]);

            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(rewardRoute.recipient);
            users[i] = address(this);
            recipients[i] = rewardRoute.recipient;
            actions[i] = rewardRoute.tokenAction;
        }

        distributor.claimWithRecipient(
            users, rewardTokens, cumulativeAmounts, proofs, recipients, emptyDatas
        );

        _processClaimedRewards(rewardTokens, recipients, actions, balancesBefore);
    }

    function _processClaimedRewards(
        address[] calldata rewardTokens,
        address[] memory recipients,
        TokenAction[] memory actions,
        uint256[] memory balancesBefore
    ) private {
        uint256[] memory received = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            uint256 balanceAfter = IERC20(rewardTokens[i]).balanceOf(recipients[i]);
            require(
                balanceAfter > balancesBefore[i],
                MerklClaimedNoReward(rewardTokens[i], recipients[i])
            );

            received[i] = balanceAfter - balancesBefore[i];
        }

        for (uint256 i; i < rewardTokens.length; ++i) {
            address finalToken = rewardTokens[i];
            uint256 finalAmount = received[i];
            address finalRecipient = recipients[i];

            if (actions[i] == TokenAction.PUSH_TO_PROTOCOL) {
                uint256 protocolBalanceBefore = _protocolBalance(rewardTokens[i]);
                _pushToProtocol(rewardTokens[i], received[i]);

                uint256 protocolBalanceAfter = _protocolBalance(rewardTokens[i]);
                require(
                    protocolBalanceAfter > protocolBalanceBefore,
                    MerklClaimedNoReward(rewardTokens[i], address(this))
                ); // TODO: new error ? ProtocolDepositFailed(token)

                finalToken = address(protocolTokens[rewardTokens[i]]);
                finalAmount = protocolBalanceAfter - protocolBalanceBefore;

                _increaseProtocolBalanceWithoutFee(rewardTokens[i], finalAmount);
            } else if (actions[i] == TokenAction.UNWRAP_TO_OWNER) {
                finalToken = yieldTokenByProtocolToken[rewardTokens[i]];
                finalAmount = _pullFromProtocolToOwner(finalToken, type(uint256).max);
                finalRecipient = owner;
            } else if (actions[i] == TokenAction.KEEP_IN_MODULE) {
                address yieldToken = yieldTokenByProtocolToken[rewardTokens[i]];
                _increaseProtocolBalanceWithoutFee(yieldToken, received[i]);
            }

            emit MerklClaimed(
                address(distributor),
                rewardTokens[i],
                received[i],
                finalRecipient,
                finalToken,
                finalAmount,
                _msgSender()
            );
        }
    }

    function _classifyReward(address rewardToken) private returns (RewardRoute memory rewardRoute) {
        if (isProtocolToken[rewardToken]) {
            address yieldToken = _getYieldToken(rewardToken);

            return RewardRoute({
                recipient: address(this),
                yieldToken: yieldToken,
                tokenAction: yieldTokensData[yieldToken].active
                    ? TokenAction.KEEP_IN_MODULE
                    : TokenAction.UNWRAP_TO_OWNER
            });
        }

        if (yieldTokensData[rewardToken].active) {
            return RewardRoute({
                recipient: address(this),
                yieldToken: rewardToken,
                tokenAction: TokenAction.PUSH_TO_PROTOCOL
            });
        }

        return RewardRoute({
            recipient: owner, yieldToken: rewardToken, tokenAction: TokenAction.SEND_TO_OWNER
        });
    }
}
