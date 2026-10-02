// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { Vm } from "forge-std/src/Vm.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Errors } from "@openzeppelin/contracts/utils/Errors.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { TangemYieldProcessor } from "contracts/infra/TangemYieldProcessor.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract TangemYieldProcessorMulticallTest is YieldModuleFixture {
    bytes32 internal constant SOFT_EXIT_PROCESSED_EVENT_SIG =
        keccak256("SoftExitProcessed(address,address,uint256,uint8,bytes)");

    address internal riskService = makeAddr("riskService");

    function setUp() public override {
        super.setUp();

        vm.startPrank(backend);
        processor.grantRole(processor.RISK_SERVICE_ROLE(), riskService);
        vm.stopPrank();

        _registerGeneralImplementation();
    }

    /*  batching  */

    function test_multicall_SuspendsEveryModuleInBatch() public {
        YieldModuleHarness[] memory modules = _deployModules(3);

        vm.prank(riskService);
        processor.multicall(_suspendCalls(modules));

        for (uint i; i < modules.length; ++i) {
            assertTrue(modules[i].entrySuspended(address(yieldToken)));
        }
    }

    function test_multicall_EmitsEventsFromProcessor() public {
        YieldModuleHarness[] memory modules = _deployModules(2);

        for (uint i; i < modules.length; ++i) {
            vm.expectEmit(address(processor));
            emit TangemYieldProcessor.TokenSuspended(address(modules[i]));
        }

        vm.prank(riskService);
        processor.multicall(_suspendCalls(modules));
    }

    function test_multicall_ExitsEveryModuleInBatch() public {
        YieldModuleHarness[] memory modules = _deployEnteredModules(2);
        bytes[] memory calls = new bytes[](2);
        for (uint i; i < modules.length; ++i) {
            calls[i] = abi.encodeCall(processor.exitProtocol, (address(modules[i]), address(yieldToken), 0));
        }

        vm.prank(backend);
        processor.multicall(calls);

        for (uint i; i < modules.length; ++i) {
            assertEq(modules[i].protocolBalance(address(yieldToken)), 0);
            (, bool active,) = modules[i].yieldTokensData(address(yieldToken));
            assertFalse(active);
        }
    }

    /*  caller identity  */

    function test_multicall_ChecksRoleOfCaller_NotOfProcessor() public {
        YieldModuleHarness[] memory modules = _deployEnteredModules(1);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(processor.exitProtocol, (address(modules[0]), address(yieldToken), 0));

        vm.expectRevert(_accessControlError(riskService, processor.PROTOCOL_EXITER_ROLE()));
        vm.prank(riskService);
        processor.multicall(calls);
    }

    function test_multicall_Reverts_WhenCallerLacksRole() public {
        YieldModuleHarness[] memory modules = _deployModules(1);

        vm.expectRevert(_accessControlError(otherAccount, processor.RISK_SERVICE_ROLE()));
        vm.prank(otherAccount);
        processor.multicall(_suspendCalls(modules));
    }

    function test_multicall_IgnoresSpoofedSenderSuffix() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        bytes memory spoofed = abi.encodePacked(abi.encodeCall(processor.multicall, (_suspendCalls(modules))), backend);

        vm.prank(otherAccount);
        (bool success, bytes memory returndata) = address(processor).call(spoofed);

        assertFalse(success);
        assertEq(returndata, _accessControlError(otherAccount, processor.RISK_SERVICE_ROLE()));
    }

    function test_multicall_KeepsCaller_InNestedMulticall() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        bytes[] memory outer = new bytes[](1);
        outer[0] = abi.encodeCall(processor.multicall, (_suspendCalls(modules)));

        vm.expectRevert(_accessControlError(otherAccount, processor.RISK_SERVICE_ROLE()));
        vm.prank(otherAccount);
        processor.multicall(outer);

        vm.prank(riskService);
        processor.multicall(outer);

        assertTrue(modules[0].entrySuspended(address(yieldToken)));
    }

    /*  atomicity  */

    function test_multicall_RevertsWholeBatch_WhenOneCallReverts() public {
        YieldModuleHarness[] memory modules = _deployModules(3);
        _suspendViaProcessor(modules[1]);

        vm.expectRevert(IYieldModule.TokenEntrySuspended.selector);
        vm.prank(riskService);
        processor.multicall(_suspendCalls(modules));

        assertFalse(modules[0].entrySuspended(address(yieldToken)));
        assertFalse(modules[2].entrySuspended(address(yieldToken)));
    }

    function test_multicall_BubblesInnerRevertWithoutCallIndex() public {
        YieldModuleHarness[] memory modules = _deployModules(3);
        _suspendViaProcessor(modules[2]);

        vm.prank(riskService);
        (bool success, bytes memory returndata) =
            address(processor).call(abi.encodeCall(processor.multicall, (_suspendCalls(modules))));

        assertFalse(success);
        assertEq(returndata, abi.encodeWithSelector(IYieldModule.TokenEntrySuspended.selector));
    }

    function test_multicall_EmitsTwoVerdicts_WhenSameModuleSoftExitedTwice() public {
        YieldModuleHarness[] memory modules = _deployEnteredModules(1);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("softExit(address,address)", address(modules[0]), address(yieldToken));
        calls[1] = calls[0];

        vm.recordLogs();
        vm.prank(riskService);
        processor.multicall(calls);

        assertEq(_countProcessorLogs(vm.getRecordedLogs(), SOFT_EXIT_PROCESSED_EVENT_SIG), 2);
    }

    /*  pause  */

    function test_multicall_Reverts_WhenPaused() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        vm.prank(backend);
        processor.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(riskService);
        processor.multicall(_suspendCalls(modules));
    }

    function test_multicall_RollsBackPause_WhenLaterCallReverts() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(processor.pause, ());
        calls[1] = abi.encodeCall(processor.suspendToken, (address(modules[0]), address(yieldToken)));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(backend);
        processor.multicall(calls);

        assertFalse(processor.paused());
    }

    /*  role management inside a batch  */

    function test_multicall_Reverts_WhenGrantingRoleWithoutAdmin() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IAccessControl.grantRole, (processor.RISK_SERVICE_ROLE(), otherAccount));

        vm.expectRevert(_accessControlError(riskService, processor.DEFAULT_ADMIN_ROLE()));
        vm.prank(riskService);
        processor.multicall(calls);
    }

    function test_multicall_Reverts_WhenRenouncingRoleOfAnotherAccount() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IAccessControl.renounceRole, (processor.RISK_SERVICE_ROLE(), backend));

        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        vm.prank(riskService);
        processor.multicall(calls);
    }

    function test_multicall_RevertsWholeBatch_WhenCallerRenouncesRoleMidBatch() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        bytes32 riskRole = processor.RISK_SERVICE_ROLE();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IAccessControl.renounceRole, (riskRole, riskService));
        calls[1] = abi.encodeCall(processor.suspendToken, (address(modules[0]), address(yieldToken)));

        vm.expectRevert(_accessControlError(riskService, riskRole));
        vm.prank(riskService);
        processor.multicall(calls);

        assertTrue(processor.hasRole(riskRole, riskService));
    }

    /*  malformed input  */

    function test_multicall_Reverts_WhenValueSent() public {
        YieldModuleHarness[] memory modules = _deployModules(1);
        vm.deal(riskService, 1 ether);

        vm.prank(riskService);
        (bool success,) =
            address(processor).call{ value: 1 }(abi.encodeCall(processor.multicall, (_suspendCalls(modules))));

        assertFalse(success);
        assertEq(address(processor).balance, 0);
    }

    function test_multicall_Reverts_WhenCallDataIsEmpty() public {
        bytes[] memory calls = new bytes[](1);

        vm.expectRevert(Errors.FailedCall.selector);
        vm.prank(riskService);
        processor.multicall(calls);
    }

    function test_multicall_Reverts_WhenSelectorIsUnknown() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSignature("execute(bytes)", "");

        vm.expectRevert(Errors.FailedCall.selector);
        vm.prank(riskService);
        processor.multicall(calls);
    }

    /*  helpers  */

    function _deployModules(uint count) internal returns (YieldModuleHarness[] memory modules) {
        modules = new YieldModuleHarness[](count);
        for (uint i; i < count; ++i) {
            address moduleOwner = makeAddr(string.concat("moduleOwner", vm.toString(i)));
            modules[i] = _deployYieldModuleWithFunds(moduleOwner, INITIAL_OWNER_BALANCE);
        }
    }

    function _deployEnteredModules(uint count) internal returns (YieldModuleHarness[] memory modules) {
        modules = _deployModules(count);
        for (uint i; i < count; ++i) {
            _enterViaProcessor(modules[i], 0);
        }
    }

    function _suspendCalls(YieldModuleHarness[] memory modules) internal view returns (bytes[] memory calls) {
        calls = new bytes[](modules.length);
        for (uint i; i < modules.length; ++i) {
            calls[i] = abi.encodeCall(processor.suspendToken, (address(modules[i]), address(yieldToken)));
        }
    }

    function _countProcessorLogs(Vm.Log[] memory entries, bytes32 eventSig) internal view returns (uint count) {
        for (uint i; i < entries.length; ++i) {
            if (entries[i].emitter == address(processor) && entries[i].topics[0] == eventSig) {
                ++count;
            }
        }
    }
}
