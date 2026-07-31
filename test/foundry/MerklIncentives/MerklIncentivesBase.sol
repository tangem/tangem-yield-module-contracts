// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { TestERC20 } from "contracts/test/TestERC20.sol";
import { AaveV3YieldModuleBase } from "test/foundry/TangemAaveV3YieldModule/AaveV3YieldModuleBase.sol";
import { YieldModuleHarness } from "test/foundry/harnesses/YieldModuleHarness.sol";

abstract contract MerklIncentivesBase is AaveV3YieldModuleBase {
    uint internal constant CLAIM_MAX_SERVICE_FEE_RATE = 1500;

    YieldModuleHarness ym;

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
        _claimSingleAsOwner(rewardToken, amount, CLAIM_MAX_SERVICE_FEE_RATE);
    }

    function _claimSingleAsOwner(address rewardToken, uint amount, uint maxServiceFeeRate) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(tokens, amounts, proofs, maxServiceFeeRate);
    }

    function _claimSingleAsBE(address rewardToken, uint amount) internal {
        _claimSingleAsBE(rewardToken, amount, CLAIM_MAX_SERVICE_FEE_RATE);
    }

    function _claimSingleAsBE(address rewardToken, uint amount, uint maxServiceFeeRate) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        vm.prank(address(processor));
        ym.claimMerklRewardsBE(tokens, amounts, proofs, maxServiceFeeRate);
    }

    function _claimSingleAsOwnerViaForwarder(address rewardToken, uint amount) internal {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, amount);

        bytes memory data = abi.encodeCall(
            IMerklIncentives.claimMerklRewardsOwner, (tokens, amounts, proofs, CLAIM_MAX_SERVICE_FEE_RATE)
        );

        _executeViaForwarder(address(ym), data, 0);
    }
}
