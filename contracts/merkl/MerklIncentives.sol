// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IMerklDistributor } from "../interfaces/IMerklDistributor.sol";
import { IMerklIncentives } from "../interfaces/IMerklIncentives.sol";

import { Requires } from "../common/Requires.sol";
import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";

abstract contract MerklIncentives is IMerklIncentives, YieldModuleLiquidUpgradeable {
    using Requires for uint;
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
        uint balanceBefore;
        uint received;
    }

    constructor(address distributor_) {
        distributor_.requireNotZero();
        distributor = IMerklDistributor(distributor_);
    }

    function claimMerklRewardsOwner(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyOwner nonReentrant {
        _claimMerklRewards(rewardTokens, cumulativeAmounts, proofs);
    }

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyProcessor nonReentrant {
        _claimMerklRewards(rewardTokens, cumulativeAmounts, proofs);
    }

    function _claimMerklRewards(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) private {
        require(rewardTokens.length > 0, RewardTokensEmpty());
        require(
            rewardTokens.length == cumulativeAmounts.length
                && cumulativeAmounts.length == proofs.length,
            RewardTokensLengthsMismatch()
        );

        RewardRoute[] memory routes = new RewardRoute[](rewardTokens.length);
        address[] memory users = new address[](rewardTokens.length);
        address[] memory recipients = new address[](rewardTokens.length);
        bytes[] memory emptyDatas = new bytes[](rewardTokens.length);

        for (uint i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            // Check for duplicate reward tokens
            for (uint k; k < i; ++k) {
                require(rewardTokens[k] != rewardTokens[i], DuplicateRewardToken(rewardTokens[i]));
            }

            RewardRoute memory route = _classifyRewardRoute(rewardTokens[i]);

            route.balanceBefore = IERC20(rewardTokens[i]).balanceOf(route.recipient);
            routes[i] = route;
            users[i] = address(this);
            recipients[i] = route.recipient;
        }

        distributor.claimWithRecipient(
            users, rewardTokens, cumulativeAmounts, proofs, recipients, emptyDatas
        );

        _processClaimedRewards(rewardTokens, routes);
    }

    function _classifyRewardRoute(address rewardToken) private returns (RewardRoute memory route) {
        route.recipient = address(this);

        if (isProtocolToken[rewardToken]) {
            route.yieldToken = _getYieldToken(rewardToken);
            route.tokenAction = yieldTokensData[route.yieldToken].active
                ? TokenAction.KEEP_IN_MODULE
                : TokenAction.UNWRAP_TO_OWNER;
        } else if (yieldTokensData[rewardToken].active) {
            route.yieldToken = rewardToken;
            route.tokenAction = TokenAction.PUSH_TO_PROTOCOL;
        } else {
            route.recipient = owner;
            route.tokenAction = TokenAction.SEND_TO_OWNER;
        }
    }

    function _processClaimedRewards(
        address[] calldata rewardTokens,
        RewardRoute[] memory routes
    ) private {
        for (uint i; i < rewardTokens.length; ++i) {
            uint balanceAfter = IERC20(rewardTokens[i]).balanceOf(routes[i].recipient);

            require(
                balanceAfter > routes[i].balanceBefore,
                MerklClaimedNoReward(rewardTokens[i], routes[i].recipient)
            );

            routes[i].received = balanceAfter - routes[i].balanceBefore;
        }

        for (uint i; i < rewardTokens.length; ++i) {
            _routeClaimedReward(rewardTokens[i], routes[i]);
        }
    }

    function _routeClaimedReward(address rewardToken, RewardRoute memory route) private {
        address finalToken = rewardToken;
        uint finalAmount = route.received;
        address finalRecipient = route.recipient;

        if (route.tokenAction == TokenAction.PUSH_TO_PROTOCOL) {
            uint protocolBalanceBefore = _protocolBalance(rewardToken);
            _pushToProtocol(rewardToken, route.received);
            uint protocolBalanceAfter = _protocolBalance(rewardToken);
            require(
                protocolBalanceAfter > protocolBalanceBefore, ProtocolDepositFailed(rewardToken)
            );

            finalToken = address(protocolTokens[rewardToken]);
            finalAmount = protocolBalanceAfter - protocolBalanceBefore;

            _increaseProtocolBalanceWithoutFee(rewardToken, finalAmount);
        } else if (route.tokenAction == TokenAction.UNWRAP_TO_OWNER) {
            finalToken = route.yieldToken;
            finalAmount = _pullFromProtocolToOwner(route.yieldToken, route.received);
            finalRecipient = owner;
        } else if (route.tokenAction == TokenAction.KEEP_IN_MODULE) {
            _increaseProtocolBalanceWithoutFee(route.yieldToken, route.received);
        }

        emit MerklClaimed(
            address(distributor),
            rewardToken,
            route.received,
            finalRecipient,
            finalToken,
            finalAmount,
            _msgSender()
        );
    }
}
