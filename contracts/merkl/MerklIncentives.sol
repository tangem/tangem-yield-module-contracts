// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMerklIncentives } from "../interfaces/IMerklIncentives.sol";
import { IMerklDistributor } from "../interfaces/external/IMerklDistributor.sol";

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
        KEEP_IN_MODULE,
        SEND_TO_OWNER
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

        uint[] memory balancesBefore = new uint[](rewardTokens.length);
        address[] memory users = new address[](rewardTokens.length);
        bytes[] memory emptyDatas = new bytes[](rewardTokens.length);

        for (uint i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            // Check for duplicate reward tokens
            for (uint k; k < i; ++k) {
                require(rewardTokens[k] != rewardTokens[i], DuplicateRewardToken(rewardTokens[i]));
            }

            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
            users[i] = address(this);
        }

        distributor.claimWithRecipient(users, rewardTokens, cumulativeAmounts, proofs, users, emptyDatas);

        _settleClaimedRewards(rewardTokens, balancesBefore, maxServiceFeeRate);
    }

    function _settleClaimedRewards(
        address[] calldata rewardTokens,
        uint[] memory balancesBefore,
        uint maxServiceFeeRate
    ) private {
        uint[] memory received = new uint[](rewardTokens.length);

        for (uint i; i < rewardTokens.length; ++i) {
            uint balanceAfter = IERC20(rewardTokens[i]).balanceOf(address(this));

            require(balanceAfter > balancesBefore[i], MerklClaimedNoReward(rewardTokens[i]));

            received[i] = balanceAfter - balancesBefore[i];
        }

        uint serviceFeeRate = processor.serviceFeeRate();
        address feeReceiver = processor.feeReceiver();

        require(
            serviceFeeRate <= maxServiceFeeRate && serviceFeeRate <= MAX_MERKL_SERVICE_FEE_RATE,
            ServiceFeeRateExceedsMax(serviceFeeRate)
        );
        feeReceiver.requireNotZero();

        for (uint i; i < rewardTokens.length; ++i) {
            _routeClaimedReward(rewardTokens[i], received[i], serviceFeeRate, feeReceiver);
        }
    }

    function _routeClaimedReward(address rewardToken, uint received, uint serviceFeeRate, address feeReceiver) private {
        (address yieldToken, TokenAction tokenAction) = _classifyRewardRoute(rewardToken);

        uint serviceFee = _takeServiceFee(rewardToken, received, serviceFeeRate, feeReceiver);
        uint netAmount = received - serviceFee;

        address finalToken = rewardToken;
        uint finalAmount = netAmount;
        address finalRecipient = address(this);

        if (tokenAction == TokenAction.PUSH_TO_PROTOCOL) {
            _pushToProtocol(rewardToken, netAmount);
            finalToken = address(protocolTokens[rewardToken]);

            _increaseProtocolBalanceWithoutFee(rewardToken, netAmount);
        } else if (tokenAction == TokenAction.UNWRAP_TO_OWNER) {
            finalToken = yieldToken;
            finalAmount = _pullFromProtocolToOwner(yieldToken, netAmount);
            finalRecipient = owner;
        } else if (tokenAction == TokenAction.KEEP_IN_MODULE) {
            _increaseProtocolBalanceWithoutFee(yieldToken, netAmount);
        } else {
            IERC20(rewardToken).safeTransfer(owner, netAmount);
            finalRecipient = owner;
        }

        emit MerklClaimed(
            rewardToken,
            received,
            serviceFeeRate,
            serviceFee,
            feeReceiver,
            finalRecipient,
            finalToken,
            finalAmount,
            _msgSender()
        );
    }

    function _classifyRewardRoute(address rewardToken) private returns (address yieldToken, TokenAction tokenAction) {
        if (isProtocolToken[rewardToken]) {
            yieldToken = _resolveYieldToken(rewardToken);
            tokenAction = yieldTokensData[yieldToken].active ? TokenAction.KEEP_IN_MODULE : TokenAction.UNWRAP_TO_OWNER;
        } else if (yieldTokensData[rewardToken].active) {
            yieldToken = rewardToken;
            tokenAction = TokenAction.PUSH_TO_PROTOCOL;
        } else {
            tokenAction = TokenAction.SEND_TO_OWNER;
        }
    }

    function _takeServiceFee(
        address rewardToken,
        uint received,
        uint serviceFeeRate,
        address feeReceiver
    ) private returns (uint fee) {
        fee = received * serviceFeeRate / PRECISION;

        if (fee == 0) return fee;

        IERC20(rewardToken).safeTransfer(feeReceiver, fee);
    }
}
