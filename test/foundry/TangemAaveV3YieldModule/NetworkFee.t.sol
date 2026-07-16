// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "../AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract NetworkFeeTest is AaveV3YieldModuleBase {
    uint240 internal constant NEW_MAX_NETWORK_FEE = 5e6;

    TangemAaveV3YieldModuleHarness internal yieldModule;

    function setUp() public override {
        super.setUp();
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
}
