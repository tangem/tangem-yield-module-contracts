// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";

contract TangemYieldProcessorTest is YieldModuleFixture {
    address internal newFeeReceiver = makeAddr("newFeeReceiver");

    /*  enterProtocol  */

    function test_enterProtocol_Reverts_WhenNotProtocolEnterer() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.PROTOCOL_ENTERER_ROLE()));
        vm.prank(otherAccount);
        processor.enterProtocol(address(1), address(yieldToken), 0);
    }

    /*  exitProtocol  */

    function test_exitProtocol_Reverts_WhenNotProtocolExiter() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.PROTOCOL_EXITER_ROLE()));
        vm.prank(otherAccount);
        processor.exitProtocol(address(1), address(yieldToken), 0);
    }

    /*  collectServiceFee  */

    function test_collectServiceFee_EmitsServiceFeeCollected() public {
        _registerGeneralImplementation();
        YieldModuleHarness yieldModule = _deployEnteredRevenueModule(owner);

        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.ServiceFeeCollected(address(yieldModule));

        _collectViaProcessor(yieldModule);
    }

    function test_collectServiceFee_Reverts_WhenNotServiceFeeCollector() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.SERVICE_FEE_COLLECTOR_ROLE()));
        vm.prank(otherAccount);
        processor.collectServiceFee(address(1), address(yieldToken));
    }

    /*  claimMerklRewards  */

    function test_claimMerklRewards_Reverts_WhenNotMerklClaimer() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.CLAIM_MERKL_REWARDS_ROLE()));
        vm.prank(otherAccount);
        processor.claimMerklRewards(address(1), new address[](0), new uint[](0), new bytes32[][](0));
    }

    /*  setFeeReceiver  */

    function test_setFeeReceiver_SetsNewFeeReceiver() public {
        assertEq(processor.feeReceiver(), feeReceiver);

        vm.prank(backend);
        processor.setFeeReceiver(newFeeReceiver);

        assertEq(processor.feeReceiver(), newFeeReceiver);
    }

    function test_setFeeReceiver_EmitsFeeReceiverSet() public {
        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.FeeReceiverSet(newFeeReceiver);

        vm.prank(backend);
        processor.setFeeReceiver(newFeeReceiver);
    }

    function test_setFeeReceiver_Reverts_WhenNotPropertySetter() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.PROPERTY_SETTER_ROLE()));
        vm.prank(otherAccount);
        processor.setFeeReceiver(newFeeReceiver);
    }

    /*  setServiceFeeRate  */

    function test_setServiceFeeRate_Reverts_WhenFeeRateExceedsPrecision() public {
        vm.expectRevert(TangemYieldProcessor.InvalidFeeRate.selector);
        vm.prank(backend);
        processor.setServiceFeeRate(PRECISION + 1);
    }

    function test_setServiceFeeRate_AllowsFeeRateEqualToPrecision() public {
        vm.prank(backend);
        processor.setServiceFeeRate(PRECISION);

        assertEq(processor.serviceFeeRate(), PRECISION);
    }

    function test_setServiceFeeRate_EmitsFeeRateSet() public {
        vm.expectEmit(address(processor));
        emit TangemYieldProcessor.FeeRateSet(PRECISION);

        vm.prank(backend);
        processor.setServiceFeeRate(PRECISION);
    }

    function test_constructor_Reverts_WhenFeeRateExceedsPrecision() public {
        vm.expectRevert(TangemYieldProcessor.InvalidFeeRate.selector);
        new TangemYieldProcessor(feeReceiver, PRECISION + 1);
    }

    /*  pause  */

    function test_pause_PausesProcessor() public {
        assertFalse(processor.paused());

        vm.prank(backend);
        processor.pause();

        assertTrue(processor.paused());
    }

    function test_pause_EmitsPaused() public {
        vm.expectEmit(address(processor));
        emit Pausable.Paused(backend);

        vm.prank(backend);
        processor.pause();
    }

    function test_pause_Reverts_WhenNotPauser() public {
        vm.expectRevert(_accessControlError(otherAccount, processor.PAUSER_ROLE()));
        vm.prank(otherAccount);
        processor.pause();
    }

    function test_pause_BlocksProtocolOperations() public {
        vm.prank(backend);
        processor.pause();

        vm.startPrank(backend);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.enterProtocol(address(1), address(yieldToken), 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.exitProtocol(address(1), address(yieldToken), 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.collectServiceFee(address(1), address(yieldToken));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.claimMerklRewards(address(1), new address[](0), new uint[](0), new bytes32[][](0));

        vm.stopPrank();
    }

    /*  unpause  */

    function test_unpause_UnpausesProcessor() public {
        vm.prank(backend);
        processor.pause();
        assertTrue(processor.paused());

        vm.prank(backend);
        processor.unpause();

        assertFalse(processor.paused());
    }

    function test_unpause_RestoresProtocolOperations() public {
        _registerGeneralImplementation();
        YieldModuleHarness yieldModule = _deployYieldModuleWithFunds(owner, INITIAL_OWNER_BALANCE);

        vm.startPrank(backend);
        processor.pause();
        processor.unpause();
        vm.stopPrank();

        _enterViaProcessor(yieldModule, 0);

        assertEq(yieldModule.protocolBalance(address(yieldToken)), INITIAL_OWNER_BALANCE);
    }

    function test_unpause_EmitsUnpaused() public {
        vm.prank(backend);
        processor.pause();

        vm.expectEmit(address(processor));
        emit Pausable.Unpaused(backend);

        vm.prank(backend);
        processor.unpause();
    }

    function test_unpause_Reverts_WhenNotPauser() public {
        vm.prank(backend);
        processor.pause();

        vm.expectRevert(_accessControlError(otherAccount, processor.PAUSER_ROLE()));
        vm.prank(otherAccount);
        processor.unpause();
    }
}
