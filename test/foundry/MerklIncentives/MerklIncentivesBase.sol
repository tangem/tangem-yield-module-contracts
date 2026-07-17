// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TestERC20 } from "contracts/test/TestERC20.sol";
import { AaveV3YieldModuleBase } from "test/foundry/TangemAaveV3YieldModule/AaveV3YieldModuleBase.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";

abstract contract MerklIncentivesBase is AaveV3YieldModuleBase {
    TangemAaveV3YieldModuleHarness ym;

    address[] rewardTokens;
    uint[] cumulativeAmounts;
    bytes32[][] proofs;

    function _createRewardToken() internal returns (TestERC20 token) {
        token = new TestERC20("RewardToken", "RWD", 18);
    }

    function _createRewardTokens(uint count) internal returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);

        for(uint i; i < tokens.length; ++i) {
            tokens[i] = _createRewardToken();
        }
    }

    function _fundMerklDistributor(address token, uint amount) internal {
        deal(token, address(merklDistributor), amount, true);
    }

    function _claimSingleAsOwner(address rewardToken, uint amount) internal {
        (
            address[] memory tokens,
            uint[] memory amounts,
            bytes32[][] memory proofs_
        ) = _singleClaimArgs(rewardToken, amount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(tokens, amounts, proofs_);
    }

    function _claimSingleAsBE(address rewardToken, uint amount) internal {
        (
            address[] memory tokens,
            uint[] memory amounts,
            bytes32[][] memory proofs_
        ) = _singleClaimArgs(rewardToken, amount);

        vm.prank(address(processor));
        ym.claimMerklRewardsBE(tokens, amounts, proofs_);
    }

    function _singleClaimArgs(
        address rewardToken,
        uint amount
    )
        private
        pure
        returns (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs_)
    {
        tokens = new address[](1);
        tokens[0] = rewardToken;
        amounts = new uint[](1);
        amounts[0] = amount;
        proofs_ = new bytes32[][](1);
    }

    function _claimSingleAsOwnerViaForwarder(address rewardToken, uint amount) internal {
        (
            address[] memory tokens,
            uint[] memory amounts,
            bytes32[][] memory proofs_
        ) = _singleClaimArgs(rewardToken, amount);

        bytes memory data =
            abi.encodeCall(IMerklIncentives.claimMerklRewardsOwner, (tokens, amounts, proofs_));

        _executeViaForwarder(address(ym), data, 0);
    }
}
