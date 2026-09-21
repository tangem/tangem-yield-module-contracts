// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { MerklIncentivesFixture, TestERC20 } from "./MerklIncentivesFixture.sol";
import { IMerklIncentives } from "contracts/interfaces/IMerklIncentives.sol";
import { IMerklDistributor } from "contracts/interfaces/external/IMerklDistributor.sol";
import { MerklTokenWrapperMock } from "contracts/test/MerklTokenWrapperMock.sol";

/// A Merkl campaign may distribute a token wrapper instead of the reward token itself: the claim
/// burns the wrapper at the recipient and pays out the underlying token. The distributor must
/// therefore be given the wrapper, while the module must measure its credit on the received token.
contract TokenWrapperRewardsTest is MerklIncentivesFixture {
    uint internal constant WRAPPER_BASE = 1e9;

    function setUp() public override {
        super.setUp();

        ym = _deployEnteredRevenueModule(owner);
    }

    /* Distributor call */

    function test_claim_PassesWrapperToDistributor_NotReceivedToken() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        (
            address[] memory rewardTokens,
            address[] memory receivedTokens,
            uint[] memory cumulativeAmounts,
            bytes32[][] memory proofs
        ) = _singleClaimArgs(address(wrapper), address(underlying), AMOUNT);

        address[] memory expectedModule = new address[](1);
        expectedModule[0] = address(ym);

        vm.expectCall(
            address(merklDistributor),
            abi.encodeCall(
                IMerklDistributor.claimWithRecipient,
                (expectedModule, rewardTokens, cumulativeAmounts, proofs, expectedModule, new bytes[](1))
            )
        );

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, receivedTokens, cumulativeAmounts, proofs);

        assertEq(merklDistributor.claimed(address(ym), address(wrapper)), AMOUNT);
        assertEq(merklDistributor.claimed(address(ym), address(underlying)), 0);
    }

    /* SEND_TO_OWNER */

    function test_claim_SendsToOwner_WhenWrapperDeliversUnknownToken() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        _claimSingleAsOwner(address(wrapper), address(underlying), AMOUNT);

        assertEq(underlying.balanceOf(owner), AMOUNT - fee);
        assertEq(underlying.balanceOf(feeReceiver), fee);
        assertEq(underlying.balanceOf(address(ym)), 0);
        assertEq(wrapper.balanceOf(address(ym)), 0);
        assertEq(wrapper.totalSupply(), 0);
    }

    function test_claim_EmitsMerklClaimed_WithWrapperAndReceivedToken() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(wrapper),
            address(underlying),
            AMOUNT,
            fee,
            owner,
            address(underlying),
            AMOUNT - fee,
            owner
        );

        _claimSingleAsOwner(address(wrapper), address(underlying), AMOUNT);
    }

    function test_claimMerklRewardsBE_SendsToOwner_WhenWrapperDeliversUnknownToken() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);

        _claimSingleAsBE(address(wrapper), address(underlying), AMOUNT);

        assertEq(underlying.balanceOf(owner), AMOUNT - fee);
        assertEq(underlying.balanceOf(feeReceiver), fee);
        assertEq(underlying.balanceOf(address(ym)), 0);
    }

    /* PUSH_TO_PROTOCOL */

    function test_claim_PushesToProtocol_WhenWrapperDeliversActiveYieldToken() public {
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(yieldToken));
        _fundRewardWrapper(wrapper, YIELD_AMOUNT);

        uint poolBalanceBefore = yieldToken.balanceOf(address(pool));
        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        _claimSingleAsOwner(address(wrapper), address(yieldToken), YIELD_AMOUNT);

        assertEq(yieldToken.balanceOf(address(pool)), poolBalanceBefore + net);
        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore + net);
        assertEq(yieldToken.balanceOf(feeReceiver), fee);
        assertEq(yieldToken.balanceOf(address(ym)), 0);
        assertEq(yieldToken.balanceOf(owner), 0);
    }

    /* KEEP_IN_MODULE */

    function test_claim_KeepsInModule_WhenWrapperDeliversProtocolToken() public {
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(protocolToken));
        _fundRewardWrapper(wrapper, YIELD_AMOUNT);

        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        _claimSingleAsOwner(address(wrapper), address(protocolToken), YIELD_AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore + net);
        assertEq(protocolToken.balanceOf(feeReceiver), fee);
        assertEq(protocolToken.balanceOf(owner), 0);
    }

    /* UNWRAP_TO_OWNER */

    function test_claim_UnwrapsToOwner_WhenWrapperDeliversProtocolTokenOfDeactivatedYieldToken() public {
        _withdrawAndDeactivate(ym, owner, address(yieldToken));

        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(protocolToken));
        _fundRewardWrapper(wrapper, YIELD_AMOUNT);

        uint ownerBalanceBefore = yieldToken.balanceOf(owner);
        uint feeReceiverBalanceBefore = protocolToken.balanceOf(feeReceiver);

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        _claimSingleAsOwner(address(wrapper), address(protocolToken), YIELD_AMOUNT);

        assertEq(yieldToken.balanceOf(owner), ownerBalanceBefore + net);
        assertEq(protocolToken.balanceOf(feeReceiver), feeReceiverBalanceBefore + fee);
        assertEq(protocolToken.balanceOf(address(ym)), 0);
        assertEq(ym.protocolBalance(address(yieldToken)), 0);
    }

    /* Partial and empty deliveries */

    function test_claim_ChargesFeeOnDeliveredAmount_WhenWrapperWithholdsClaimFee() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        // a claim-fee wrapper keeps a share of the campaign amount, so the module is credited less
        wrapper.setClaimFeeRate(WRAPPER_BASE / 10);

        uint delivered = AMOUNT - AMOUNT / 10;
        uint fee = _expectedRewardFee(delivered);

        vm.expectEmit(address(ym));
        emit IMerklIncentives.MerklClaimed(
            address(wrapper),
            address(underlying),
            delivered,
            fee,
            owner,
            address(underlying),
            delivered - fee,
            owner
        );

        _claimSingleAsOwner(address(wrapper), address(underlying), AMOUNT);

        assertEq(underlying.balanceOf(owner), delivered - fee);
        assertEq(underlying.balanceOf(feeReceiver), fee);
        assertEq(underlying.balanceOf(address(ym)), 0);
    }

    function test_claim_Reverts_WhenWrapperDeliversNothing() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        wrapper.setClaimFeeRate(WRAPPER_BASE);

        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.MerklClaimedNoReward.selector, address(underlying)));

        _claimSingleAsOwner(address(wrapper), address(underlying), AMOUNT);
    }

    /* Mis-declared received token */

    function test_claim_Reverts_WhenReceivedTokenIsTheWrapper() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock wrapper = _createRewardWrapper(address(underlying));
        _fundRewardWrapper(wrapper, AMOUNT);

        // the wrapper is burned on claim, so its balance never grows: naming it as the received
        // token is the exact case the receivedTokens parameter exists to avoid
        vm.expectRevert(abi.encodeWithSelector(IMerklIncentives.MerklClaimedNoReward.selector, address(wrapper)));

        _claimSingleAsOwner(address(wrapper), address(wrapper), AMOUNT);
    }

    /* Shared underlying */

    /// Two campaigns can wrap the same reward token, and then a single batch credits the module
    /// once per wrapper but on one shared balance.
    function test_claim_ChargesFeeOncePerDelivery_WhenTwoWrappersDeliverProtocolToken() public {
        MerklTokenWrapperMock firstWrapper = _createRewardWrapper(address(protocolToken));
        MerklTokenWrapperMock secondWrapper = _createRewardWrapper(address(protocolToken));

        _fundRewardWrapper(firstWrapper, YIELD_AMOUNT);
        _fundRewardWrapper(secondWrapper, YIELD_AMOUNT);

        uint protocolBalanceBefore = ym.protocolBalance(address(yieldToken));

        uint fee = _expectedRewardFee(YIELD_AMOUNT);
        uint net = YIELD_AMOUNT - fee;

        _claimPair(firstWrapper, secondWrapper, address(protocolToken), YIELD_AMOUNT);

        assertEq(ym.protocolBalance(address(yieldToken)), protocolBalanceBefore + 2 * net);
        assertEq(protocolToken.balanceOf(feeReceiver), 2 * fee);
    }

    function test_claim_ForwardsSharedUnderlyingOnce_WhenTwoWrappersDeliverUnknownToken() public {
        TestERC20 underlying = _createRewardToken();
        MerklTokenWrapperMock firstWrapper = _createRewardWrapper(address(underlying));
        MerklTokenWrapperMock secondWrapper = _createRewardWrapper(address(underlying));

        _fundRewardWrapper(firstWrapper, AMOUNT);
        _fundRewardWrapper(secondWrapper, AMOUNT);

        uint fee = _expectedRewardFee(AMOUNT);
        uint net = AMOUNT - fee;

        _claimPair(firstWrapper, secondWrapper, address(underlying), AMOUNT);

        assertEq(underlying.balanceOf(owner), 2 * net);
        assertEq(underlying.balanceOf(feeReceiver), 2 * fee);
        assertEq(underlying.balanceOf(address(ym)), 0);
    }

    /* helpers */

    function _claimPair(
        MerklTokenWrapperMock firstWrapper,
        MerklTokenWrapperMock secondWrapper,
        address receivedToken,
        uint amount
    ) internal {
        (address[] memory rewardTokens, uint[] memory cumulativeAmounts, bytes32[][] memory proofs) = _claimArgs(2);
        address[] memory receivedTokens = new address[](2);

        rewardTokens[0] = address(firstWrapper);
        rewardTokens[1] = address(secondWrapper);
        receivedTokens[0] = receivedToken;
        receivedTokens[1] = receivedToken;
        cumulativeAmounts[0] = amount;
        cumulativeAmounts[1] = amount;

        vm.prank(owner);
        ym.claimMerklRewardsOwner(rewardTokens, receivedTokens, cumulativeAmounts, proofs);
    }
}
