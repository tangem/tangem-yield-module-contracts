// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { YieldModuleBase } from "../YieldModuleBase.sol";
import { YieldModuleGeneralHarness } from "../harnesses/YieldModuleGeneralHarness.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract YieldTokenLifecycleTest is YieldModuleBase {
    uint240 internal constant MAX_NETWORK_FEE = 20e6;
    uint240 internal constant NEW_MAX_NETWORK_FEE = 30e6;

    YieldModuleGeneralHarness internal yieldModule;
    YieldModuleGeneralHarness internal initModule;
    address internal initOwner = makeAddr("initOwner");

    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();

        // Main module: yield token active then deactivated (reactivateToken tests)
        yieldModule = _deployGeneralYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        // Separate module with no active yield token (initYieldToken tests)
        initModule = _deployGeneralYieldModule(initOwner, address(0), 0);
    }

    /*  initYieldToken  */

    function test_initYieldToken_InitializesYieldToken() public {
        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);

        (bool initialized, bool active, uint240 maxNetworkFee) =
            initModule.yieldTokensData(address(yieldToken));
        assertTrue(initialized);
        assertTrue(active);
        assertEq(maxNetworkFee, MAX_NETWORK_FEE);

        address pt = address(initModule.protocolTokens(address(yieldToken)));
        assertNotEq(pt, address(0));
        assertTrue(initModule.isProtocolToken(pt));
    }

    function test_initYieldToken_RevertsTokenAlreadyInitialized() public {
        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);

        vm.expectRevert(IYieldModule.TokenAlreadyInitialized.selector);
        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    function test_initYieldToken_RevertsTokenAlreadyInitialized_WhenDeactivated() public {
        vm.expectRevert(IYieldModule.TokenAlreadyInitialized.selector);
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    function test_initYieldToken_RevertsOnlyOwnerOrFactory() public {
        vm.expectRevert(IYieldModule.OnlyOwnerOrFactory.selector);
        vm.prank(otherAccount);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    function test_initYieldToken_EmitsYieldTokenInitialized() public {
        address freshOwner = makeAddr("freshOwner");
        YieldModuleGeneralHarness freshModule = _deployGeneralYieldModule(freshOwner, address(0), 0);

        vm.expectEmit(false, false, false, false, address(freshModule));
        emit IYieldModule.YieldTokenInitialized(address(yieldToken), address(0), MAX_NETWORK_FEE);

        vm.prank(freshOwner);
        freshModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);

        assertNotEq(address(freshModule.protocolTokens(address(yieldToken))), address(0));
    }

    /*  reactivateToken  */

    function test_reactivateToken_ReactivatesYieldToken() public {
        (, bool active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertFalse(active);

        vm.prank(owner);
        yieldModule.reactivateToken(address(yieldToken), NEW_MAX_NETWORK_FEE);

        (, active,) = yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(active);
    }

    function test_reactivateToken_SetsNewMaxNetworkFee() public {
        (,, uint240 maxNetworkFee) = yieldModule.yieldTokensData(address(yieldToken));
        assertEq(maxNetworkFee, DEFAULT_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.reactivateToken(address(yieldToken), NEW_MAX_NETWORK_FEE);

        (,, maxNetworkFee) = yieldModule.yieldTokensData(address(yieldToken));
        assertEq(maxNetworkFee, NEW_MAX_NETWORK_FEE);
    }

    function test_reactivateToken_RevertsTokenNotInitialized() public {
        address uninitializedToken = makeAddr("uninitializedToken");

        vm.expectRevert(IYieldModule.TokenNotInitialized.selector);
        vm.prank(owner);
        yieldModule.reactivateToken(uninitializedToken, NEW_MAX_NETWORK_FEE);
    }

    function test_reactivateToken_RevertsTokenAlreadyActive() public {
        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE); // active after init

        vm.expectRevert(IYieldModule.TokenAlreadyActive.selector);
        vm.prank(initOwner);
        initModule.reactivateToken(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }

    function test_reactivateToken_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.reactivateToken(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }

    function test_reactivateToken_EmitsTokenReactivated() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.TokenReactivated(address(yieldToken), NEW_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.reactivateToken(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }
}
