// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { SwapExecutionRegistry } from "contracts/core/SwapExecutionRegistry.sol";
import { ISwapExecutionRegistry } from "contracts/interfaces/ISwapExecutionRegistry.sol";

import { BaseTest } from "../BaseTest.sol";

contract SwapExecutionRegistryTest is BaseTest {
    address internal target = makeAddr("target");
    address internal spender = makeAddr("spender");

    SwapExecutionRegistry public registry;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(backend);
        registry = new SwapExecutionRegistry(backend);
        vm.label(address(registry), "swapExecutionRegistry");
    }

    function _expectUnauthorized(address account) internal {
        bytes32 role = registry.ALLOWLIST_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, account, role
            )
        );
    }

    /* constructor */

    function test_constructor_GrantsRolesToAdmin() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), backend));
        assertTrue(registry.hasRole(registry.ALLOWLIST_ADMIN_ROLE(), backend));
    }

    function test_constructor_Reverts_WhenAdminIsZero() public {
        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        new SwapExecutionRegistry(address(0));
    }

    /* setTargetAllowed */

    function test_setTargetAllowed_SetsFlagAndEmitsTargetAllowedSet() public {
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(target, true);

        vm.prank(backend);
        registry.setTargetAllowed(target, true);

        assertTrue(registry.allowedTargets(target));
    }

    function test_setTargetAllowed_Reverts_WhenTargetIsZero() public {
        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setTargetAllowed(address(0), true);
    }

    function test_setTargetAllowed_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setTargetAllowed(target, true);
    }

    /* setSpenderAllowed */

    function test_setSpenderAllowed_SetsFlagAndEmitsSpenderAllowedSet() public {
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spender, true);

        vm.prank(backend);
        registry.setSpenderAllowed(spender, true);

        assertTrue(registry.allowedSpenders(spender));
    }

    function test_setSpenderAllowed_Reverts_WhenSpenderIsZero() public {
        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setSpenderAllowed(address(0), true);
    }

    function test_setSpenderAllowed_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setSpenderAllowed(spender, true);
    }

    function testFuzz_setSpenderAllowed(address fuzzSpender, bool allowed) public {
        vm.assume(fuzzSpender != address(0));

        vm.prank(backend);
        registry.setSpenderAllowed(fuzzSpender, allowed);

        assertEq(registry.allowedSpenders(fuzzSpender), allowed);
    }

    /* setTargetsAllowed */

    function test_setTargetsAllowed_SetsManyTargetsAllowedAndEmitsForEach() public {
        address[] memory targets = _twoAddresses(target, spender);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[0], true);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[1], true);

        vm.prank(backend);
        registry.setTargetsAllowed(targets, true);

        assertTrue(registry.allowedTargets(targets[0]));
        assertTrue(registry.allowedTargets(targets[1]));
    }

    function test_setTargetsAllowed_SetsManyTargetsDisallowedAndEmitsForEach() public {
        address[] memory targets = _twoAddresses(target, spender);

        vm.startPrank(backend);
        registry.setTargetsAllowed(targets, true);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[0], false);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[1], false);

        registry.setTargetsAllowed(targets, false);
        vm.stopPrank();

        assertFalse(registry.allowedTargets(targets[0]));
        assertFalse(registry.allowedTargets(targets[1]));
    }

    function test_setTargetsAllowed_Reverts_WhenAnyTargetIsZero() public {
        address[] memory targets = new address[](3);
        targets[0] = target;
        targets[1] = address(0);
        targets[2] = spender;

        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setTargetsAllowed(targets, true);
    }

    function test_setTargetsAllowed_AllowsEmptyArray() public {
        vm.prank(backend);
        registry.setTargetsAllowed(new address[](0), true);
    }

    function test_setTargetsAllowed_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setTargetsAllowed(_twoAddresses(target, spender), true);
    }

    /* setSpendersAllowed */

    function test_setSpendersAllowed_SetsManySpendersAllowedAndEmitsForEach() public {
        address[] memory spenders = _twoAddresses(target, spender);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[0], true);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[1], true);

        vm.prank(backend);
        registry.setSpendersAllowed(spenders, true);

        assertTrue(registry.allowedSpenders(spenders[0]));
        assertTrue(registry.allowedSpenders(spenders[1]));
    }

    function test_setSpendersAllowed_SetsManySpendersDisallowedAndEmitsForEach() public {
        address[] memory spenders = _twoAddresses(target, spender);

        vm.startPrank(backend);
        registry.setSpendersAllowed(spenders, true);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[0], false);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[1], false);

        registry.setSpendersAllowed(spenders, false);
        vm.stopPrank();

        assertFalse(registry.allowedSpenders(spenders[0]));
        assertFalse(registry.allowedSpenders(spenders[1]));
    }

    function test_setSpendersAllowed_Reverts_WhenAnySpenderIsZero() public {
        address[] memory spenders = new address[](3);
        spenders[0] = target;
        spenders[1] = address(0);
        spenders[2] = spender;

        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setSpendersAllowed(spenders, true);
    }

    function test_setSpendersAllowed_AllowsEmptyArray() public {
        vm.prank(backend);
        registry.setSpendersAllowed(new address[](0), true);
    }

    function test_setSpendersAllowed_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setSpendersAllowed(_twoAddresses(target, spender), true);
    }

    /* setTargetsAllowedMany */

    function test_setTargetsAllowedMany_SetsPerItemStatusesAndEmitsForEach() public {
        address[] memory targets = _twoAddresses(target, spender);
        bool[] memory statuses = _twoStatuses(true, false);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[0], true);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.TargetAllowedSet(targets[1], false);

        vm.prank(backend);
        registry.setTargetsAllowedMany(targets, statuses);

        assertTrue(registry.allowedTargets(targets[0]));
        assertFalse(registry.allowedTargets(targets[1]));
    }

    function test_setTargetsAllowedMany_Reverts_WhenLengthsMismatch() public {
        address[] memory targets = _twoAddresses(target, spender);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;

        vm.expectRevert(ISwapExecutionRegistry.LengthMismatch.selector);
        vm.prank(backend);
        registry.setTargetsAllowedMany(targets, statuses);
    }

    function test_setTargetsAllowedMany_Reverts_WhenAnyTargetIsZero() public {
        address[] memory targets = _twoAddresses(target, address(0));
        bool[] memory statuses = _twoStatuses(true, false);

        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setTargetsAllowedMany(targets, statuses);
    }

    function test_setTargetsAllowedMany_AllowsEmptyArrays() public {
        vm.prank(backend);
        registry.setTargetsAllowedMany(new address[](0), new bool[](0));
    }

    function test_setTargetsAllowedMany_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setTargetsAllowedMany(_twoAddresses(target, spender), _twoStatuses(true, true));
    }

    /* setSpendersAllowedMany */

    function test_setSpendersAllowedMany_SetsPerItemStatusesAndEmitsForEach() public {
        address[] memory spenders = _twoAddresses(target, spender);
        bool[] memory statuses = _twoStatuses(false, true);

        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[0], false);
        vm.expectEmit(address(registry));
        emit ISwapExecutionRegistry.SpenderAllowedSet(spenders[1], true);

        vm.prank(backend);
        registry.setSpendersAllowedMany(spenders, statuses);

        assertFalse(registry.allowedSpenders(spenders[0]));
        assertTrue(registry.allowedSpenders(spenders[1]));
    }

    function test_setSpendersAllowedMany_Reverts_WhenLengthsMismatch() public {
        address[] memory spenders = _twoAddresses(target, spender);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;

        vm.expectRevert(ISwapExecutionRegistry.LengthMismatch.selector);
        vm.prank(backend);
        registry.setSpendersAllowedMany(spenders, statuses);
    }

    function test_setSpendersAllowedMany_Reverts_WhenAnySpenderIsZero() public {
        address[] memory spenders = _twoAddresses(target, address(0));
        bool[] memory statuses = _twoStatuses(true, false);

        vm.expectRevert(ISwapExecutionRegistry.ZeroAddress.selector);
        vm.prank(backend);
        registry.setSpendersAllowedMany(spenders, statuses);
    }

    function test_setSpendersAllowedMany_AllowsEmptyArrays() public {
        vm.prank(backend);
        registry.setSpendersAllowedMany(new address[](0), new bool[](0));
    }

    function test_setSpendersAllowedMany_Reverts_WhenNotAllowlistAdmin() public {
        _expectUnauthorized(otherAccount);
        vm.prank(otherAccount);
        registry.setSpendersAllowedMany(_twoAddresses(target, spender), _twoStatuses(true, true));
    }

    /* views */

    function test_views_ReturnFalseByDefault() public view {
        assertFalse(registry.allowedTargets(otherAccount));
        assertFalse(registry.allowedSpenders(otherAccount));
    }

    /* helpers */

    function _twoAddresses(
        address first,
        address second
    ) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = first;
        arr[1] = second;
    }

    function _twoStatuses(bool first, bool second) internal pure returns (bool[] memory arr) {
        arr = new bool[](2);
        arr[0] = first;
        arr[1] = second;
    }
}
