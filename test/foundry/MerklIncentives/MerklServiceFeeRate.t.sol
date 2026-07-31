// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { MerklIncentivesBase, TestERC20 } from "./MerklIncentivesBase.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { PRECISION } from "contracts/resources/Constants.sol";

// TODO: review this tests
contract MerklServiceFeeRateTest is MerklIncentivesBase {
    TestERC20 internal rewardToken;

    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);

        rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);
    }

    /* caller-approved maximum */

    function test_claim_Reverts_WhenRateExceedsCallerMax() public {
        _setServiceFeeRate(SERVICE_FEE_RATE + 1);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, SERVICE_FEE_RATE + 1));

        _claimSingleAsOwner(address(rewardToken), AMOUNT, SERVICE_FEE_RATE);
    }

    function test_claim_Reverts_WhenCallerMaxIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, SERVICE_FEE_RATE)
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT, 0);
    }

    function test_claim_Succeeds_WhenRateEqualsCallerMax() public {
        _claimSingleAsOwner(address(rewardToken), AMOUNT, SERVICE_FEE_RATE);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
    }

    function test_claim_Succeeds_WhenCallerMaxIsZeroAndRateIsZero() public {
        _setServiceFeeRate(0);

        _claimSingleAsOwner(address(rewardToken), AMOUNT, 0);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
    }

    function testFuzz_claim_Reverts_WhenRateExceedsCallerMax(uint rate, uint callerMax) public {
        rate = bound(rate, 1, CLAIM_MAX_SERVICE_FEE_RATE);
        callerMax = bound(callerMax, 0, rate - 1);

        _setServiceFeeRate(rate);

        vm.expectRevert(
            abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, rate)
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT, callerMax);
    }

    /* contract-level cap */

    function test_claim_Reverts_WhenRateExceedsContractCap() public {
        uint rate = CLAIM_MAX_SERVICE_FEE_RATE + 1;
        _setServiceFeeRate(rate);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, rate));

        _claimSingleAsOwner(address(rewardToken), AMOUNT, rate);
    }

    function test_claim_Reverts_WhenRateExceedsContractCap_BE() public {
        uint rate = CLAIM_MAX_SERVICE_FEE_RATE + 1;
        _setServiceFeeRate(rate);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, rate));

        _claimSingleAsBE(address(rewardToken), AMOUNT, type(uint).max);
    }

    function test_claim_Succeeds_WhenRateEqualsContractCap() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE);

        _claimSingleAsOwner(address(rewardToken), AMOUNT, CLAIM_MAX_SERVICE_FEE_RATE);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
    }

    function testFuzz_claim_Reverts_WhenRateExceedsContractCap(uint rate) public {
        rate = bound(rate, CLAIM_MAX_SERVICE_FEE_RATE + 1, PRECISION);

        _setServiceFeeRate(rate);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, rate));

        _claimSingleAsOwner(address(rewardToken), AMOUNT, type(uint).max);
    }

    /* ordering: cheap array validation runs before the rate check */

    function test_claim_Reverts_WithEntryError_WhenRateAlsoExceedsCap() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE + 1);

        (address[] memory tokens, uint[] memory amounts, bytes32[][] memory proofs) = _claimArgs(0);

        vm.expectRevert(IMerklIncentives.RewardTokensEmpty.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(tokens, amounts, proofs, 0);
    }
}
