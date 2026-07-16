// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TestERC20 } from "contracts/test/TestERC20.sol";
import { YieldModuleBase } from "test/foundry/YieldModuleBase.sol";
import { YieldModuleGeneralHarness } from "test/foundry/harnesses/YieldModuleGeneralHarness.sol";

/// Test base for MerklIncentives. Uses the general YieldModuleGeneralHarness deployed by
/// YieldModuleBase so Merkl reward-claiming logic can be tested without coupling to a
/// specific yield protocol (AAVE, Morpho, etc.).
abstract contract MerklIncentivesBase is YieldModuleBase {
    address[] rewardTokens;
    uint[] cumulativeAmounts;
    bytes32[][] proofs;

    function setUp() public virtual override {
        super.setUp();

        _registerGeneralImplementation();
    }

    function _deployModuleWithMerkl(
        address moduleOwner,
        address yieldTokenAddr,
        uint240 maxNetworkFee
    ) internal returns (YieldModuleGeneralHarness yieldModule) {
        vm.prank(moduleOwner);
        factory.deployYieldModule(moduleOwner, yieldTokenAddr, maxNetworkFee);

        yieldModule =
            YieldModuleGeneralHarness(payable(factory.calculateYieldModuleAddress(moduleOwner)));
        vm.label(address(yieldModule), "YMWithMerkl");
    }

    function _createRewardToken() internal returns (TestERC20 token) {
        token = new TestERC20();
    }

    function _createRewardTokens(uint count) internal returns (TestERC20[] memory tokens) {
        tokens = new TestERC20[](count);

        for(uint i; i < tokens.length; ++i) {
            tokens[i] = _createRewardToken();
        }
    }

    // TODO: fixture helpers (_deployMerklModule, _deployEnteredMerklModule, etc.)
    // TODO: actor wrappers (_claimMerklRewardsOwner, _claimMerklRewardsBE)
    // TODO: _fundMerklReward (pending MerklDistributorMock logic)
}
