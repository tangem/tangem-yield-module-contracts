// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMerklIncentives } from "../interfaces/IMerklIncentives.sol";
import { IMerklDistributor } from "../interfaces/external/IMerklDistributor.sol";

import { PRECISION } from "../common/Constants.sol";
import { Requires } from "../common/Requires.sol";
import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";

abstract contract MerklIncentives is IMerklIncentives, YieldModuleLiquidUpgradeable {
    using SafeERC20 for IERC20;
    using Requires for uint;
    using Requires for address;

    uint public constant MAX_MERKL_SERVICE_FEE_RATE = 1500;

    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
        address[] calldata receivedTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyOwner nonReentrant {
        _claimMerklRewards(rewardTokens, receivedTokens, cumulativeAmounts, proofs);
    }

    function claimMerklRewardsBE(
        address[] calldata rewardTokens,
        address[] calldata receivedTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external onlyProcessor nonReentrant {
        _claimMerklRewards(rewardTokens, receivedTokens, cumulativeAmounts, proofs);
    }

    function _claimMerklRewards(
        address[] calldata rewardTokens,
        address[] calldata receivedTokens,
        uint[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) private {
        require(rewardTokens.length > 0, RewardTokensEmpty());
        require(
            rewardTokens.length == receivedTokens.length && receivedTokens.length == cumulativeAmounts.length
                && cumulativeAmounts.length == proofs.length,
            RewardTokensLengthsMismatch()
        );

        uint serviceFeeRate = processor.serviceFeeRate();
        address feeReceiver = processor.feeReceiver();

        if (serviceFeeRate > MAX_MERKL_SERVICE_FEE_RATE) {
            serviceFeeRate = MAX_MERKL_SERVICE_FEE_RATE;
        }

        feeReceiver.requireNotZero();

        Claim memory claim = _newClaim();

        for (uint i; i < rewardTokens.length; ++i) {
            rewardTokens[i].requireNotZero();
            receivedTokens[i].requireNotZero();
            cumulativeAmounts[i].requireNotZero();

            claim.tokens[0] = rewardTokens[i];
            claim.amounts[0] = cumulativeAmounts[i];
            claim.proofs[0] = proofs[i];

            address receivedToken = receivedTokens[i];

            uint receivedAmount = _claim(receivedToken, claim);

            uint serviceFee = _takeServiceFee(receivedToken, receivedAmount, serviceFeeRate, feeReceiver);
            _routeClaimedReward(claim.tokens[0], receivedToken, receivedAmount, serviceFee);
        }
    }

    function _claim(address receivedToken, Claim memory claim) private returns (uint receivedAmount) {
        bool isNative = receivedToken == NATIVE;

        uint balanceBefore = isNative ? address(this).balance : IERC20(receivedToken).balanceOf(address(this));

        distributor.claimWithRecipient(claim.users, claim.tokens, claim.amounts, claim.proofs, claim.users, claim.datas);

        uint balanceAfter = isNative ? address(this).balance : IERC20(receivedToken).balanceOf(address(this));

        require(balanceAfter > balanceBefore, MerklClaimedNoReward(receivedToken));

        receivedAmount = balanceAfter - balanceBefore;
    }

    function _routeClaimedReward(
        address rewardToken,
        address receivedToken,
        uint receivedAmount,
        uint serviceFee
    ) private {
        (address yieldToken, TokenAction tokenAction) = _classifyRewardRoute(receivedToken);

        uint netAmount = receivedAmount - serviceFee;

        address finalToken = receivedToken;
        uint finalAmount = netAmount;
        address finalRecipient = address(this);

        if (tokenAction == TokenAction.PUSH_TO_PROTOCOL) {
            _pushToProtocol(receivedToken, netAmount);
            finalToken = address(protocolTokens[receivedToken]);

            _increaseProtocolBalanceWithoutFee(receivedToken, netAmount);
        } else if (tokenAction == TokenAction.UNWRAP_TO_OWNER) {
            finalToken = yieldToken;
            finalAmount = _pullFromProtocolToOwner(yieldToken, netAmount);
            finalRecipient = owner;
        } else if (tokenAction == TokenAction.KEEP_IN_MODULE) {
            _increaseProtocolBalanceWithoutFee(yieldToken, netAmount);
        } else {
            _transferReward(receivedToken, owner, netAmount);
            finalRecipient = owner;
        }

        emit MerklClaimed(
            rewardToken,
            receivedToken,
            receivedAmount,
            serviceFee,
            finalRecipient,
            finalToken,
            finalAmount,
            _msgSender()
        );
    }

    function _classifyRewardRoute(address receivedToken) private returns (address yieldToken, TokenAction tokenAction) {
        if (isProtocolToken[receivedToken]) {
            yieldToken = _resolveYieldToken(receivedToken);
            tokenAction = yieldTokensData[yieldToken].active ? TokenAction.KEEP_IN_MODULE : TokenAction.UNWRAP_TO_OWNER;
        } else if (_isEntryAllowed(receivedToken)) {
            yieldToken = receivedToken;
            tokenAction = TokenAction.PUSH_TO_PROTOCOL;
        } else {
            tokenAction = TokenAction.SEND_TO_OWNER;
        }
    }

    function _takeServiceFee(
        address receivedToken,
        uint receivedAmount,
        uint serviceFeeRate,
        address feeReceiver
    ) private returns (uint fee) {
        fee = receivedAmount * serviceFeeRate / PRECISION;

        if (fee > 0) {
            _transferReward(receivedToken, feeReceiver, fee);
        }
    }

    function _transferReward(address receivedToken, address to, uint amount) private {
        if (receivedToken == NATIVE) {
            (bool success,) = to.call{ value: amount }("");
            require(success, NativeTransferFailed());

            return;
        }

        IERC20(receivedToken).safeTransfer(to, amount);
    }

    function _newClaim() private view returns (Claim memory claim) {
        claim.users = new address[](1);
        claim.tokens = new address[](1);
        claim.amounts = new uint[](1);
        claim.proofs = new bytes32[][](1);
        claim.datas = new bytes[](1);

        claim.users[0] = address(this);
    }
}
