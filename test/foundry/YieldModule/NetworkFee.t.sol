// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { YieldModuleBase } from "../YieldModuleBase.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract NetworkFeeTest is YieldModuleBase {
    uint240 internal constant NEW_MAX_NETWORK_FEE = 5e6;

    YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();
        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_setYieldTokenMaxNetworkFee_SetsNewMaxNetworkFee() public {
        (,, uint240 maxNetworkFee) = yieldModule.yieldTokensData(address(yieldToken));
        assertEq(maxNetworkFee, DEFAULT_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.setYieldTokenMaxNetworkFee(address(yieldToken), NEW_MAX_NETWORK_FEE);

        (,, maxNetworkFee) = yieldModule.yieldTokensData(address(yieldToken));
        assertEq(maxNetworkFee, NEW_MAX_NETWORK_FEE);
    }

    function test_setYieldTokenMaxNetworkFee_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.setYieldTokenMaxNetworkFee(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }

    function test_setYieldTokenMaxNetworkFee_EmitsTokenMaxNetworkFeeSet() public {
        vm.expectEmit(address(yieldModule));
        emit IYieldModule.TokenMaxNetworkFeeSet(address(yieldToken), NEW_MAX_NETWORK_FEE);

        vm.prank(owner);
        yieldModule.setYieldTokenMaxNetworkFee(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }

    function test_setYieldTokenMaxNetworkFee_RevertsTokenNotInitialized() public {
        address uninitializedToken = makeAddr("uninitializedToken");

        vm.expectRevert(IYieldModule.TokenNotInitialized.selector);
        vm.prank(owner);
        yieldModule.setYieldTokenMaxNetworkFee(uninitializedToken, NEW_MAX_NETWORK_FEE);
    }

    function test_setYieldTokenMaxNetworkFee_RevertsTokenNotActive() public {
        vm.prank(owner);
        yieldModule.withdrawAndDeactivate(address(yieldToken));

        vm.expectRevert(IYieldModule.TokenNotActive.selector);
        vm.prank(owner);
        yieldModule.setYieldTokenMaxNetworkFee(address(yieldToken), NEW_MAX_NETWORK_FEE);
    }

    /*  calculateFee  */

    function test_calculateFee_ReturnsNetworkFeeWhenServiceFeeIsZero() public view {
        // fresh module, no revenue => service fee is zero
        assertEq(yieldModule.calculateFee(address(yieldToken), NETWORK_FEE), NETWORK_FEE);
    }

    function test_calculateFee_ReturnsServiceFeePlusNetworkFee() public {
        YieldModuleHarness revenueModule = _deployEnteredRevenueModule(otherAccount);

        assertEq(
            revenueModule.calculateFee(address(yieldToken), NETWORK_FEE),
            ACCUMULATED_SERVICE_FEE + NETWORK_FEE
        );
    }

    function test_calculateFee_AllowsNetworkFeeEqualToMax() public view {
        assertEq(
            yieldModule.calculateFee(address(yieldToken), DEFAULT_MAX_NETWORK_FEE),
            DEFAULT_MAX_NETWORK_FEE
        );
    }

    function test_calculateFee_RevertsNetworkFeeExceedsMax() public {
        vm.expectRevert(IYieldModule.NetworkFeeExceedsMax.selector);
        yieldModule.calculateFee(address(yieldToken), uint(DEFAULT_MAX_NETWORK_FEE) + 1);
    }
}
