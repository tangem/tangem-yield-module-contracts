// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { PRECISION } from "contracts/common/Constants.sol";
import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";

contract TangemYieldProcessorTest is YieldModuleFixture {
    address internal newFeeReceiver = makeAddr("newFeeReceiver");

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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, otherAccount, processor.PROPERTY_SETTER_ROLE()
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, otherAccount, processor.PAUSER_ROLE()
            )
        );
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

        vm.stopPrank();
    }

    function test_pause_BlocksRiskServiceOperations() public {
        vm.prank(backend);
        processor.pause();

        vm.startPrank(backend);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.softExit(address(1), address(yieldToken));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.softExit(address(1), address(yieldToken), AMOUNT);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.suspendToken(address(1), address(yieldToken));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        processor.resumeAndEnterProtocol(address(1), address(yieldToken));

        vm.stopPrank();
    }

    /*  Access control  */

    function test_RiskServiceFunctions_Revert_WhenNotRiskService() public {
        bytes memory unauthorized = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, otherAccount, processor.RISK_SERVICE_ROLE()
        );

        vm.startPrank(otherAccount);

        vm.expectRevert(unauthorized);
        processor.softExit(address(1), address(yieldToken));

        vm.expectRevert(unauthorized);
        processor.softExit(address(1), address(yieldToken), AMOUNT);

        vm.expectRevert(unauthorized);
        processor.suspendToken(address(1), address(yieldToken));

        vm.expectRevert(unauthorized);
        processor.resumeAndEnterProtocol(address(1), address(yieldToken));

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

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, otherAccount, processor.PAUSER_ROLE()
            )
        );
        vm.prank(otherAccount);
        processor.unpause();
    }
}
