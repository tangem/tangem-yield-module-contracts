// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { ReentrancyGuardTransientUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { MerklIncentivesFixture, YieldModuleHarness } from "./MerklIncentivesFixture.sol";
import { ReentrantERC20 } from "contracts/test/ReentrantERC20.sol";

contract WeirdRewardTokensTest is MerklIncentivesFixture {
    bytes32 internal constant REENTRANCY_GUARD_SLOT =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /*  reentrancy guard  */

    function test_claim_Reverts_WhenRewardTokenReentersClaim() public {
        ReentrantERC20 token = new ReentrantERC20("ReentrantRewardToken", "RRT", 18);
        token.mint(address(merklDistributor), AMOUNT);

        YieldModuleHarness attackedModule = _deployYieldModule(address(token), address(0), 0);

        bytes memory claimCall = _claimCalldata(address(token));
        token.setHook(address(attackedModule), claimCall);

        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        token.execute(address(attackedModule), claimCall);
    }

    function test_claim_ReentrancyGuardUsesTransientStorage() public {
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        vm.record();
        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);
        (, bytes32[] memory writes) = vm.accesses(address(ym));

        for (uint i; i < writes.length; ++i) {
            assertTrue(writes[i] != REENTRANCY_GUARD_SLOT, "reentrancy guard must not use persistent storage");
        }
    }

    /*  helpers  */

    function _claimCalldata(address rewardToken) internal view returns (bytes memory) {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, AMOUNT);

        return abi.encodeCall(ym.claimMerklRewardsOwner, (tokens, amounts, proofs));
    }
}
