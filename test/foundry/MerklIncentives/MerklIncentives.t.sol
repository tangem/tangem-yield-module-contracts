// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { MerklIncentivesFixture, TestERC20 } from "./MerklIncentivesFixture.sol";
import { Requires } from "contracts/common/Requires.sol";
import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { MerklDistributorMock } from "contracts/test/MerklDistributorMock.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";

contract MerklIncentivesTest is MerklIncentivesFixture {
    function setUp() public override {
        super.setUp();

        ym = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    /* Constructor */

    function test_constructor_Reverts_WhenDistributorIsZero() public {
        vm.expectRevert(Requires.ZeroAddress.selector);

        new TangemAaveV3YieldModuleHarness(
            address(pool),
            address(0),
            address(processor),
            address(factory),
            address(forwarder),
            address(swapExecutionRegistry)
        );
    }

    /* Success */

    function test_claimMerklRewardsOwner_Success() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            AMOUNT,
            fee,
            owner,
            address(rewardToken),
            AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    function test_claimMerklRewardsBE_Success() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            AMOUNT,
            fee,
            owner,
            address(rewardToken),
            AMOUNT - fee,
            address(processor)
        );

        _claimSingleAsBE(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    function test_claimMerklRewards_EmitsMerklRewardsClaimed() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.MerklRewardsClaimed(address(ym));

        _claimSingleAsBE(address(rewardToken), AMOUNT);
    }

    function test_claimMerklRewardsOwner_Success_ViaForwarder() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        // the forwarder must not leak into the event: caller is the owner, not the relayer
        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(rewardToken),
            AMOUNT,
            fee,
            owner,
            address(rewardToken),
            AMOUNT - fee,
            owner
        );

        _claimSingleAsOwnerViaForwarder(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT - fee);
        assertEq(rewardToken.balanceOf(feeReceiver), fee);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    /* Gas */

    function test_claimMerklRewardsOwner_gas() public {
        vm.pauseGasMetering();

        _mintYieldToken(owner, INITIAL_OWNER_BALANCE);
        vm.startPrank(owner);
        yieldToken.approve(address(ym), type(uint).max);
        ym.enterProtocolByOwner(address(yieldToken));
        vm.stopPrank();

        _fundMerklDistributor(address(yieldToken), YIELD_AMOUNT);

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) =
            _singleClaimArgs(address(yieldToken), YIELD_AMOUNT);

        vm.prank(owner);
        vm.resumeGasMetering();
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    /* Access control */

    function test_claimMerklRewardsOwner_Reverts_WhenNotOwner() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(0);

        vm.expectRevert(IYieldModule.OnlyOwner.selector);

        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsBE_Reverts_WhenNotProcessor() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(0);

        vm.expectRevert(IYieldModule.OnlyProcessor.selector);

        ym.claimMerklRewardsBE(rewardTokens, cumulativeAmounts, proofs);
    }

    /* Entry Errors */

    function test_claimMerklRewardsOwner_Reverts_WhenRewardTokensEmpty() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(0);

        vm.expectRevert(IMerklIncentives.RewardTokensEmpty.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenAmountsLengthMismatches() public {
        (address[] memory rewardTokens,, bytes32[][] memory proofs) = _claimArgs(1);
        uint[] memory cumulativeAmounts = new uint[](0);

        vm.expectRevert(IMerklIncentives.RewardTokensLengthsMismatch.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenProofsLengthMismatches() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts,) = _claimArgs(1);
        bytes32[][] memory proofs = new bytes32[][](0);

        vm.expectRevert(IMerklIncentives.RewardTokensLengthsMismatch.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenRewardTokenIsZero() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(1);

        vm.expectRevert(abi.encodeWithSelector(Requires.ZeroAddress.selector));

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenRewardAmountIsZero() public {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(1);
        rewardTokens[0] = makeAddr("rewardToken");

        vm.expectRevert(abi.encodeWithSelector(Requires.ZeroAmount.selector));

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenDistributorRejectsProof() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.mockCallRevert(
            address(merklDistributor),
            abi.encodeWithSelector(merklDistributor.claimWithRecipient.selector),
            abi.encodeWithSelector(MerklDistributorMock.InvalidProof.selector)
        );

        vm.expectRevert(MerklDistributorMock.InvalidProof.selector);

        _claimSingleAsOwner(address(rewardToken), AMOUNT);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenDuplicateRewardToken() public {
        TestERC20 rewardToken = _createRewardToken();

        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(2);
        rewardTokens[0] = address(rewardToken);
        rewardTokens[1] = address(rewardToken);
        cumulativeAmounts[0] = AMOUNT;
        cumulativeAmounts[1] = AMOUNT;

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.DuplicateRewardToken.selector, address(rewardToken)));

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function testFuzz_claimMerklRewardsOwner_Reverts_WhenDuplicateRewardToken(uint numTokens, uint dupIndex) public {
        numTokens = bound(numTokens, 2, 10);

        TestERC20[] memory tokens = _createRewardTokens(numTokens);
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) =
            _claimArgs(numTokens);
        for (uint i; i < numTokens; ++i) {
            rewardTokens[i] = address(tokens[i]);
            cumulativeAmounts[i] = AMOUNT;
        }

        dupIndex = dupIndex % (numTokens - 1);
        address duplicate = rewardTokens[dupIndex];
        rewardTokens[numTokens - 1] = duplicate;

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.DuplicateRewardToken.selector, duplicate));

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }
}
