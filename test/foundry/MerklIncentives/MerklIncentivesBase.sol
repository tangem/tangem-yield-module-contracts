// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TestERC20 } from "contracts/test/TestERC20.sol";
import { AaveV3YieldModuleBase } from "test/foundry/TangemAaveV3YieldModule/AaveV3YieldModuleBase.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";

/// Test base for MerklIncentives. Uses the AAVE harness backed by AaveV3PoolMock so the
/// yield flow is explicit: supply moves the underlying to the pool and mints aToken 1:1,
/// revenue mints extra aToken, withdraw burns aToken and returns the underlying.
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

    /* SINGLE-TOKEN CLAIM WRAPPERS (operate on `ym`) */

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
}
