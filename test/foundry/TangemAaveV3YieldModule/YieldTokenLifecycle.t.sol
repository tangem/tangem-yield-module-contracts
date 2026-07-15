// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract InitYieldTokenTest is TangemAaveV3YieldModuleBase {
    uint240 internal constant MAX_NETWORK_FEE = 20e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        yieldModule = _deployYieldModule(owner, address(0), 0);
    }

    function test_initYieldToken_InitializesYieldToken() public {
        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);

        (bool initialized, bool active, uint240 maxNetworkFee) =
            yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(initialized);
        assertTrue(active);
        assertEq(maxNetworkFee, MAX_NETWORK_FEE);

        assertEq(address(yieldModule.protocolTokens(address(yieldToken))), address(protocolToken));
        assertTrue(yieldModule.isProtocolToken(address(protocolToken)));
    }

    function test_initYieldToken_RevertsOnlyOwnerOrFactory() public {
        vm.expectRevert(IYieldModule.OnlyOwnerOrFactory.selector);
        vm.prank(otherAccount);
        yieldModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }

    function test_initYieldToken_EmitsYieldTokenInitialized() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.YieldTokenInitialized(
            address(yieldToken),
            address(protocolToken),
            MAX_NETWORK_FEE
        );

        vm.prank(owner);
        yieldModule.initYieldToken(address(yieldToken), MAX_NETWORK_FEE);
    }
}

contract ReactivateTokenTest is TangemAaveV3YieldModuleBase {
    uint240 internal constant NEW_MAX_NETWORK_FEE = 30e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));
    }

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
