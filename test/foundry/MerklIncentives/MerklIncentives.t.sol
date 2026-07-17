// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { MerklIncentivesBase, TestERC20 } from "./MerklIncentivesBase.sol";
import { TangemAaveV3YieldModuleHarness } from "test/foundry/harnesses/TangemAaveV3YieldModuleHarness.sol";
import { Requires } from "contracts/common/Requires.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { MerklDistributorMock } from "contracts/test/MerklDistributorMock.sol";

contract MerklIncentivesTest is MerklIncentivesBase {
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

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(rewardToken),
            AMOUNT,
            owner,
            address(rewardToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwner(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    function test_claimMerklRewardsBE_Success() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(rewardToken),
            AMOUNT,
            owner,
            address(rewardToken),
            AMOUNT,
            address(processor)
        );

        _claimSingleAsBE(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
        assertEq(rewardToken.balanceOf(address(ym)), 0);
    }

    function test_claimMerklRewardsOwner_Success_ViaForwarder() public {
        TestERC20 rewardToken = _createRewardToken();
        _fundMerklDistributor(address(rewardToken), AMOUNT);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(merklDistributor),
            address(rewardToken),
            AMOUNT,
            owner,
            address(rewardToken),
            AMOUNT,
            owner
        );

        _claimSingleAsOwnerViaForwarder(address(rewardToken), AMOUNT);

        assertEq(rewardToken.balanceOf(owner), AMOUNT);
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

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(yieldToken);
        uint[] memory cumulativeAmounts = new uint[](1);
        cumulativeAmounts[0] = YIELD_AMOUNT;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.prank(owner);
        vm.resumeGasMetering();
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    /* Access control */

    function test_claimMerklRewardsOwner_Reverts_WhenNotOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);

        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsBE_Reverts_WhenNotProcessor() public {
        vm.expectRevert(IYieldModule.OnlyProcessor.selector);

        ym.claimMerklRewardsBE(rewardTokens, cumulativeAmounts, proofs);
    }

    /* Entry Errors */

    function test_claimMerklRewardsOwner_Reverts_WhenRewardTokensEmpty() public {
        vm.expectRevert(IMerklIncentives.RewardTokensEmpty.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenArraysLengthsMismatch() public {
        address[] memory rewardTokens = new address[](1);

        vm.expectRevert(IMerklIncentives.RewardTokensLengthsMismatch.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);

        uint[] memory cumulativeAmounts = new uint[](1);

        vm.expectRevert(IMerklIncentives.RewardTokensLengthsMismatch.selector);

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenRewardTokenIsZero() public {
        address[] memory rewardTokens = new address[](1);
        uint[] memory cumulativeAmounts = new uint[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectRevert(abi.encodeWithSelector(Requires.ZeroAddress.selector));

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function test_claimMerklRewardsOwner_Reverts_WhenRewardAmountIsZero() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = makeAddr("rewardToken");

        uint[] memory cumulativeAmounts = new uint[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

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

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken);
        rewardTokens[1] = address(rewardToken);

        uint[] memory cumulativeAmounts = new uint[](2);
        cumulativeAmounts[0] = AMOUNT;
        cumulativeAmounts[1] = AMOUNT;

        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMerklIncentives.DuplicateRewardToken.selector, address(rewardToken)
            )
        );

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }

    function testFuzz_claimMerklRewardsOwner_Reverts_WhenDuplicateRewardToken(
        uint numTokens,
        uint dupIndex
    ) public {
        numTokens = bound(numTokens, 2, 10);

        TestERC20[] memory tokens = _createRewardTokens(numTokens);
        address[] memory rewardTokens = new address[](numTokens);
        for (uint i; i < numTokens; ++i) {
            rewardTokens[i] = address(tokens[i]);
        }

        dupIndex = dupIndex % (numTokens - 1);
        address duplicate = rewardTokens[dupIndex];
        rewardTokens[numTokens - 1] = duplicate;

        uint[] memory cumulativeAmounts = new uint[](numTokens);
        for (uint i; i < numTokens; ++i) {
            cumulativeAmounts[i] = AMOUNT;
        }
        bytes32[][] memory proofs = new bytes32[][](numTokens);

        vm.expectRevert(
            abi.encodeWithSelector(IMerklIncentives.DuplicateRewardToken.selector, duplicate)
        );

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, cumulativeAmounts, proofs);
    }
}
