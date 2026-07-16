// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "../AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract YieldTokenLifecycleTest is AaveV3YieldModuleBase {
    uint240 internal constant MAX_NETWORK_FEE = 20e6;
    uint240 internal constant NEW_MAX_NETWORK_FEE = 30e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;
    TangemAaveV3YieldModuleHarness internal initModule;
    address internal initOwner = makeAddr("initOwner");

    function setUp() public override {
        super.setUp();

        // Main module: yield token active then deactivated (reactivateToken tests)
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        // Separate module with no active yield token (initYieldToken tests)
        initModule = _deployYieldModule(initOwner, address(0), 0);
    }

    /* ======================================================== initYieldToken ===================================================== */

    function test_initYieldToken_InitializesYieldToken() public {
        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);

        (bool initialized, bool active, uint240 maxNetworkFee) =
            initModule.yieldTokensData(address(yieldToken));
        assertTrue(initialized);
        assertTrue(active);
        assertEq(maxNetworkFee, MAX_NETWORK_FEE);

        assertEq(address(initModule.protocolTokens(address(yieldToken))), address(protocolToken));
        assertTrue(initModule.isProtocolToken(address(protocolToken)));
    }

    function test_initYieldToken_RevertsOnlyOwnerOrFactory() public {
        vm.expectRevert(IYieldModule.OnlyOwnerOrFactory.selector);
        vm.prank(otherAccount);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    function test_initYieldToken_EmitsYieldTokenInitialized() public {
        vm.expectEmit(address(initModule));
        emit IYieldModule.YieldTokenInitialized(
            address(yieldToken),
            address(protocolToken),
            MAX_NETWORK_FEE
        );

        vm.prank(initOwner);
        initModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    /* ====================================================== reactivateToken ===================================================== */

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