// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { PRECISION } from "contracts/common/Constants.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";
import { AaveV3YieldModuleFixture } from "test/foundry/TangemAaveV3YieldModule/AaveV3YieldModuleFixture.sol";
import { YieldModuleHarness } from "test/foundry/harnesses/YieldModuleHarness.sol";

abstract contract MerklIncentivesFixture is AaveV3YieldModuleFixture {
    uint internal constant CLAIM_MAX_SERVICE_FEE_RATE = 1500;

    YieldModuleHarness ym;

    function _expectedRewardFee(uint received) internal pure returns (uint) {
        return received * SERVICE_FEE_RATE / PRECISION;
    }

    function _createRewardToken() internal returns (TestERC20 token) {
        token = new TestERC20("RewardToken", "RWD", 18);
    }

    function _createRewardTokens(uint count) internal returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);

        for (uint i; i < tokens.length; ++i) {
            tokens[i] = _createRewardToken();
        }
    }

    function _fundMerklDistributor(address token, uint amount) internal {
        deal(token, address(merklDistributor), amount, true);
    }

    /* CLAIM ARG BUILDERS */

    function _claimArgs(uint count)
        internal
        pure
        returns (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs)
    {
        tokens = new address[](count);
        amounts = new uint[](count);
        proofs = new bytes32[][](count);
    }

    /// the module requires strictly ascending reward tokens, so every multi-token claim must be sorted
    function _sortClaimArgs(address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) internal pure {
        for (uint i = 1; i < tokens.length; ++i) {
            for (uint j = i; j > 0 && tokens[j - 1] > tokens[j]; --j) {
                (tokens[j - 1], tokens[j]) = (tokens[j], tokens[j - 1]);
                (amounts[j - 1], amounts[j]) = (amounts[j], amounts[j - 1]);
                (proofs[j - 1], proofs[j]) = (proofs[j], proofs[j - 1]);
            }
        }
    }

    function _singleClaimArgs(
        address rewardToken,
        uint amount
    ) internal pure returns (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) {
        (tokens, amounts, proofs) = _claimArgs(1);
        tokens[0] = rewardToken;
        amounts[0] = amount;
    }

    /* CLAIM ACTIONS */

    function _claimSingleAsOwner(address rewardToken, uint amount) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(tokens, amounts, proofs);
    }

    function _claimSingleAsBE(address rewardToken, uint amount) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        vm.prank(backend);
        processor.claimMerklRewards(address(ym), tokens, amounts, proofs);
    }

    function _claimSingleAsOwnerViaForwarder(address rewardToken, uint amount) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        bytes memory data = abi.encodeCall(IMerklIncentives.claimMerklRewardsOwner, (tokens, amounts, proofs));

        _executeViaForwarder(address(ym), data, 0);
    }
}
