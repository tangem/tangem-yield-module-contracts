// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { MerklIncentivesBase, YieldModuleHarness } from "./MerklIncentivesBase.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { ReentrantERC20 } from "contracts/test/ReentrantERC20.sol";

contract WeirdRewardTokensTest is MerklIncentivesBase {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /*  protocol token with mint tax  */

    function test_claim_PushesToProtocol_Success_WhenFeeOnTransferToken() public {
        uint tax = YIELD_AMOUNT / 10;
        protocolToken.setFixedTax(tax);
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        vm.expectEmit(true, true, true, true, address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(yieldToken),
            YIELD_AMOUNT,
            address(ym),
            address(protocolToken),
            YIELD_AMOUNT - tax,
            owner
        );

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + YIELD_AMOUNT - tax);
    }

    function test_claim_PushesToProtocol_MovesFeeCheckpointByProtocolDelta_WhenProtocolTokenHasMintTax()
        public
    {
        uint tax = YIELD_AMOUNT / 10;
        protocolToken.setFixedTax(tax);
        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        (uint checkpointBefore,) = ym.latestFeePaymentStates(address(yieldToken));

        _claimSingleAsOwner(address(yieldToken), YIELD_AMOUNT);

        (uint checkpointAfter,) = ym.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpointAfter, checkpointBefore + YIELD_AMOUNT - tax);
        assertEq(ym.protocolBalance(address(yieldToken)), PROTOCOL_BALANCE + YIELD_AMOUNT - tax);
        assertEq(ym.calculateServiceFee(address(yieldToken)), ACCUMULATED_SERVICE_FEE);
    }

    /*  reentrancy guard  */

    function test_claim_Reverts_WhenRewardTokenReentersClaim() public {
        ReentrantERC20 token = new ReentrantERC20("ReentrantRewardToken", "RRT", 18);
        token.mint(address(merklDistributor), AMOUNT);

        YieldModuleHarness attackedModule = _deployYieldModule(address(token), address(0), 0);

        bytes memory claimCall = _claimCalldata(address(token));
        token.setHook(address(attackedModule), claimCall);

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        token.execute(address(attackedModule), claimCall);
    }

    /*  helpers  */

    function _claimCalldata(address rewardToken) internal view returns (bytes memory) {
        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) =
            _singleClaimArgs(rewardToken, AMOUNT);

        return abi.encodeCall(ym.claimMerklRewardsOwner, (tokens, amounts, proofs));
    }
}
