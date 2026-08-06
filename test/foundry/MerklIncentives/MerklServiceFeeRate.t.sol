// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { PRECISION } from "contracts/common/Constants.sol";

import { MerklIncentivesFixture, TestERC20 } from "./MerklIncentivesFixture.sol";

contract MerklServiceFeeRateTest is MerklIncentivesFixture {
    TestERC20 internal rewardToken;

    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);

        rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);
    }

    function test_claim_Succeeds_WhenRateIsCurrent() public {
        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - _expectedRewardFee(AMOUNT));
        assertEq(rewardToken.balanceOf(feeReceiver), _expectedRewardFee(AMOUNT));
    }

    function test_claim_Succeeds_WhenRateIsZero() public {
        _setServiceFeeRate(0);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        // a zero rate charges nothing and skips the fee transfer entirely
        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(feeReceiver), 0);
    }

    /* contract-level cap */

    function test_claim_Succeeds_WhenRateEqualsContractCap() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        // at the cap the fee is 15% of the reward
        uint fee = AMOUNT * CLAIM_MAX_SERVICE_FEE_RATE / PRECISION;

        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
    }

    function test_claim_ClampsRate_WhenRateExceedsContractCap() public {
        _setServiceFeeRate(CLAIM_MAX_SERVICE_FEE_RATE + 1);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        // the over-cap rate is clamped down to the cap instead of reverting the claim
        uint fee = AMOUNT * CLAIM_MAX_SERVICE_FEE_RATE / PRECISION;

        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
    }

    function test_claim_ClampsRate_WhenRateIsMaximal_BE() public {
        _setServiceFeeRate(PRECISION);

        _claimSingleAsBE(address(rewardToken), AMOUNT);

        // even a 100% processor rate cannot take more than the cap
        uint fee = AMOUNT * CLAIM_MAX_SERVICE_FEE_RATE / PRECISION;

        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
    }

    function testFuzz_claim_EnforcesContractCap(uint rate) public {
        rate = bound(rate, 0, PRECISION);

        _setServiceFeeRate(rate);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        uint effectiveRate = rate > CLAIM_MAX_SERVICE_FEE_RATE ? CLAIM_MAX_SERVICE_FEE_RATE : rate;
        uint fee = AMOUNT * effectiveRate / PRECISION;

        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
    }
}
