// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMerklDistributor } from "../interfaces/IMerklDistributor.sol";
import { IMerklIncentives } from "../interfaces/IMerklIncentives.sol";

import { Requires } from "../common/Requires.sol";
import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";
import { PRECISION } from "../resources/Constants.sol";

abstract contract MerklIncentives is IMerklIncentives, YieldModuleLiquidUpgradeable {
    using SafeERC20 for IERC20;
    using Requires for uint;
    using Requires for address;

    uint public constant MAX_MERKL_SERVICE_FEE_RATE = 1500;

    IMerklDistributor public immutable distributor;

    enum TokenAction {
        PUSH_TO_PROTOCOL,
        UNWRAP_TO_OWNER,
        SEND_TO_OWNER,
        KEEP_IN_MODULE
    }

    struct RewardRoute {
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
        bytes32[][] calldata proofs,
        uint maxServiceFeeRate
    ) external onlyOwner nonReentrant {
        _claimMerklRewards(rewardTokens, cumulativeAmounts, proofs, maxServiceFeeRate);
    }

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs,
        uint maxServiceFeeRate
    ) external onlyProcessor nonReentrant {
        _claimMerklRewards(rewardTokens, cumulativeAmounts, proofs, maxServiceFeeRate);
    }

    function _claimMerklRewards(
        address[] calldata rewardTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs,
        uint maxServiceFeeRate
    ) private {
        require(rewardTokens.length > 0, RewardTokensEmpty());
        require(
            rewardTokens.length == cumulativeAmounts.length && cumulativeAmounts.length == proofs.length,
            RewardTokensLengthsMismatch()
        );

        uint serviceFeeRate = processor.serviceFeeRate();

        require(
            serviceFeeRate <= maxServiceFeeRate && serviceFeeRate <= MAX_MERKL_SERVICE_FEE_RATE,
            ServiceFeeRateExceedsMax(serviceFeeRate)
        );

        RewardRoute[] memory routes = new RewardRoute[](rewardTokens.length);
        address[] memory users = new address[](rewardTokens.length);
        bytes[] memory emptyDatas = new bytes[](rewardTokens.length);

        for (uint i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            // Check for duplicate reward tokens
            for (uint k; k < i; ++k) {
                require(rewardTokens[k] != rewardTokens[i], DuplicateRewardToken(rewardTokens[i]));
            }

            RewardRoute memory route = _classifyRewardRoute(rewardTokens[i]);

            route.balanceBefore = IERC20(rewardTokens[i]).balanceOf(address(this));
            routes[i] = route;
            users[i] = address(this);
        }

        distributor.claimWithRecipient(users, rewardTokens, cumulativeAmounts, proofs, users, emptyDatas);

        _processClaimedRewards(rewardTokens, routes, serviceFeeRate);
    }

    function _classifyRewardRoute(address rewardToken) private returns (RewardRoute memory route) {
        if (isProtocolToken[rewardToken]) {
            route.yieldToken = _resolveYieldToken(rewardToken);
            route.tokenAction =
                yieldTokensData[route.yieldToken].active ? TokenAction.KEEP_IN_MODULE : TokenAction.UNWRAP_TO_OWNER;
        } else if (yieldTokensData[rewardToken].active) {
            route.yieldToken = rewardToken;
            route.tokenAction = TokenAction.PUSH_TO_PROTOCOL;
        } else {
            route.tokenAction = TokenAction.SEND_TO_OWNER;
        }
    }

    function _processClaimedRewards(
        address[] calldata rewardTokens,
        RewardRoute[] memory routes,
        uint serviceFeeRate
    ) private {
        for (uint i; i < rewardTokens.length; ++i) {
            uint balanceAfter = IERC20(rewardTokens[i]).balanceOf(address(this));

            require(balanceAfter > routes[i].balanceBefore, MerklClaimedNoReward(rewardTokens[i]));

            routes[i].received = balanceAfter - routes[i].balanceBefore;
        }

        for (uint i; i < rewardTokens.length; ++i) {
            _routeClaimedReward(rewardTokens[i], routes[i], serviceFeeRate);
        }
    }

    function _routeClaimedReward(address rewardToken, RewardRoute memory route, uint serviceFeeRate) private {
        (uint serviceFee, address feeReceiver) = _takeServiceFee(rewardToken, route.received, serviceFeeRate);
        uint netAmount = route.received - serviceFee;

        address finalToken = rewardToken;
        uint finalAmount = netAmount;
        address finalRecipient = address(this);

        if (route.tokenAction == TokenAction.PUSH_TO_PROTOCOL) {
            _pushToProtocol(rewardToken, netAmount);
            finalToken = address(protocolTokens[rewardToken]);

            _increaseProtocolBalanceWithoutFee(rewardToken, netAmount);
        } else if (route.tokenAction == TokenAction.UNWRAP_TO_OWNER) {
            finalToken = route.yieldToken;
            finalAmount = _pullFromProtocolToOwner(route.yieldToken, netAmount);
            finalRecipient = owner;
        } else if (route.tokenAction == TokenAction.KEEP_IN_MODULE) {
            _increaseProtocolBalanceWithoutFee(route.yieldToken, netAmount);
        } else {
            IERC20(rewardToken).safeTransfer(owner, netAmount);
            finalRecipient = owner;
        }

        emit MerklClaimed(
            rewardToken,
            route.received,
            serviceFeeRate,
            serviceFee,
            feeReceiver,
            finalRecipient,
            finalToken,
            finalAmount,
            _msgSender()
        );
    }

    function _takeServiceFee(
        address rewardToken,
        uint received,
        uint serviceFeeRate
    ) private returns (uint fee, address feeReceiver) {
        fee = received * serviceFeeRate / PRECISION;

        if (fee == 0) return (0, address(0));

        feeReceiver = processor.feeReceiver();
        feeReceiver.requireNotZero();

        IERC20(rewardToken).safeTransfer(feeReceiver, fee);
    }
}
