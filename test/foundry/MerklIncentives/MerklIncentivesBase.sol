// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { YieldModuleBase } from "test/foundry/YieldModuleBase.sol";

/// Test base for MerklIncentives. Uses the generic YieldModuleGenericHarness deployed by
/// YieldModuleBase so Merkl reward-claiming logic can be tested without coupling to a
/// specific yield protocol (AAVE, Morpho, etc.).
abstract contract MerklIncentivesBase is YieldModuleBase {
    function setUp() public virtual override {
        super.setUp();

        _registerGenericImplementation();
    }

    // TODO: fixture helpers (_deployMerklModule, _deployEnteredMerklModule, etc.)
    // TODO: actor wrappers (_claimMerklRewardsOwner, _claimMerklRewardsBE)
    // TODO: _fundMerklReward (pending MerklDistributorMock logic)
}