// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { PRECISION } from "contracts/resources/Constants.sol";

import { MerklIncentivesBase, TestERC20 } from "./MerklIncentivesBase.sol";

contract MerklServiceFeeRateTest is MerklIncentivesBase {
    TestERC20 internal rewardToken;

    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);

        rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);
    }

    /* caller-approved maximum */

    function test_claim_Succeeds_WhenRateEqualsCallerMax() public {
        _claimSingleAsOwner(address(rewardToken), AMOUNT, SERVICE_FEE_RATE);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - _expectedRewardFee(AMOUNT));
        assertEq(rewardToken.balanceOf(feeReceiver), _expectedRewardFee(AMOUNT));
    }

    function test_claim_Succeeds_WhenCallerMaxIsZeroAndRateIsZero() public {
        _setServiceFeeRate(0);

        _claimSingleAsOwner(address(rewardToken), AMOUNT, 0);

        // a zero rate charges nothing and skips the fee transfer entirely
        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(feeReceiver), 0);
    }

    function test_claim_Reverts_WhenRateExceedsCallerMax() public {
        _setServiceFeeRate(SERVICE_FEE_RATE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, SERVICE_FEE_RATE + 1)
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT, SERVICE_FEE_RATE);
    }

    function test_claim_Reverts_WhenCallerMaxIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, SERVICE_FEE_RATE));

        _claimSingleAsOwner(address(rewardToken), AMOUNT, 0);
    }

    /* contract-level cap */

    function test_claim_Succeeds_WhenRateEqualsContractCap() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE);

        _claimSingleAsOwner(address(rewardToken), AMOUNT, CLAIM_MAX_SERVICE_FEE_RATE);

        // at the cap the fee is 15% of the reward
        uint fee = AMOUNT * CLAIM_MAX_SERVICE_FEE_RATE / PRECISION;

        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
    }

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

    /* both bounds together */

    function testFuzz_claim_EnforcesRateBounds(uint rate, uint callerMax) public {
        rate = bound(rate, 0, PRECISION);
        callerMax = bound(callerMax, 0, PRECISION);

        _setServiceFeeRate(rate);

        bool allowed = rate <= callerMax && rate <= CLAIM_MAX_SERVICE_FEE_RATE;

        if (!allowed) {
            vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.ServiceFeeRateExceedsMax.selector, rate));
        }

        _claimSingleAsOwner(address(rewardToken), AMOUNT, callerMax);

        if (allowed) {
            uint fee = AMOUNT * rate / PRECISION;

            assertEq(rewardToken.balanceOf(feeReceiver), fee);
            assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
        }
    }
}
