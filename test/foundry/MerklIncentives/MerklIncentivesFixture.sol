// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { PRECISION } from "contracts/common/Constants.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { MerklTokenWrapperMock } from "contracts/test/MerklTokenWrapperMock.sol";
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

    /* TOKEN WRAPPERS */

    function _createRewardWrapper(address underlying) internal returns (MerklTokenWrapperMock wrapper) {
        wrapper = new MerklTokenWrapperMock(underlying, address(merklDistributor), "WrappedReward", "wRWD");
    }

    function _fundRewardWrapper(MerklTokenWrapperMock wrapper, uint amount) internal {
        wrapper.fundDistributor(amount);
        deal(address(wrapper.underlying()), address(wrapper), amount, true);
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

    function _singleClaimArgs(
        address rewardToken,
        address receivedToken,
        uint amount
    )
        internal
        pure
        returns (
            address[] memory tokens,
            address[] memory receivedTokens,
            uint[] memory amounts,
            bytes32[][] memory proofs
        )
    {
        (tokens, amounts, proofs) = _singleClaimArgs(rewardToken, amount);

        receivedTokens = new address[](1);
        receivedTokens[0] = receivedToken;
    }

    /* CLAIM ACTIONS */

    function _claimSingleAsOwner(address rewardToken, uint amount) internal {
        _claimSingleAsOwner(rewardToken, rewardToken, amount);
    }

    function _claimSingleAsOwner(address rewardToken, address receivedToken, uint amount) internal {
        (address[] memory tokens, address[] memory receivedTokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, receivedToken, amount);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(tokens, receivedTokens, amounts, proofs);
    }

    function _claimSingleAsBE(address rewardToken, uint amount) internal {
        _claimSingleAsBE(rewardToken, rewardToken, amount);
    }

    function _claimSingleAsBE(address rewardToken, address receivedToken, uint amount) internal {
        (address[] memory tokens, address[] memory receivedTokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, receivedToken, amount);

        vm.prank(backend);
        processor.claimMerklRewards(address(ym), tokens, receivedTokens, amounts, proofs);
    }

    function _claimSingleAsOwnerViaForwarder(address rewardToken, uint amount) internal {
        (address[] memory tokens, address[] memory receivedTokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, rewardToken, amount);

        bytes memory data =
            abi.encodeCall(IMerklIncentives.claimMerklRewardsOwner, (tokens, receivedTokens, amounts, proofs));

        _executeViaForwarder(address(ym), data, 0);
    }
}
