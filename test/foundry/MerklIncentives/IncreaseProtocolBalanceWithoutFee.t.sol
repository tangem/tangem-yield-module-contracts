// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { MerklIncentivesBase } from "./MerklIncentivesBase.sol";

/// Covers _increaseProtocolBalanceWithoutFee, driven through Merkl claims
contract IncreaseProtocolBalanceWithoutFeeTest is MerklIncentivesBase {
    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    function testFuzz_claim_MovesFeeCheckpoint_OnPushToProtocol(uint amount) public {
        amount = bound(amount, 1, type(uint128).max);

        (uint checkpointBefore,) = ym.latestFeePaymentStates(address(yieldToken));
        uint feeBefore = ym.calculateServiceFee(address(yieldToken));

        _fundMerklDistributor(address(yieldToken), amount);

        _claimSingleAsOwner(address(yieldToken), amount);

        // only the net reward enters the protocol, so only the net reward moves the checkpoint
        uint netAmount = amount - _expectedRewardFee(amount);

        (uint checkpointAfter, uint rateAfter) = ym.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpointAfter, checkpointBefore + netAmount);
        assertEq(rateAfter, SERVICE_FEE_RATE);
        // the checkpoint moved together with the balance, so the net reward is never charged twice
        assertEq(ym.calculateServiceFee(address(yieldToken)), feeBefore);
    }

    function testFuzz_claim_MovesFeeCheckpoint_OnKeepInModule(uint amount) public {
        amount = bound(amount, 1, type(uint128).max);

        (uint checkpointBefore,) = ym.latestFeePaymentStates(address(yieldToken));
        uint feeBefore = ym.calculateServiceFee(address(yieldToken));

        _fundMerklDistributor(address(protocolToken), amount);

        _claimSingleAsOwner(address(protocolToken), amount);

        uint netAmount = amount - _expectedRewardFee(amount);

        (uint checkpointAfter, uint rateAfter) = ym.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpointAfter, checkpointBefore + netAmount);
        assertEq(rateAfter, SERVICE_FEE_RATE);
        assertEq(ym.calculateServiceFee(address(yieldToken)), feeBefore);
    }

    function test_claim_ClampsFeeCheckpoint_ToProtocolBalance() public {
        // checkpoint the reward cannot fit under, e.g. after protocol rounding credited less
        uint protocolBalance = ym.protocolBalance(address(yieldToken));
        ym.exposed_setLatestFeePaymentState(address(yieldToken), protocolBalance + 1, SERVICE_FEE_RATE);

        _fundMerklDistributor(address(protocolToken), YIELD_AMOUNT);

        _claimSingleAsOwner(address(protocolToken), YIELD_AMOUNT);

        (uint checkpointAfter,) = ym.latestFeePaymentStates(address(yieldToken));
        assertEq(checkpointAfter, ym.protocolBalance(address(yieldToken)));
    }
}
