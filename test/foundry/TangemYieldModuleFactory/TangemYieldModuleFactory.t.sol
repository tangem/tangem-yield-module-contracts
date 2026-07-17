// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { YieldModuleBase } from "../YieldModuleBase.sol";

import { TangemYieldModuleFactory } from "contracts/core/TangemYieldModuleFactory.sol";

contract TangemYieldModuleFactoryTest is YieldModuleBase {
    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();
    }

    function test_deployYieldModule_RevertsModuleAlreadyDeployed() public {
        _deployGeneralYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(TangemYieldModuleFactory.ModuleAlreadyDeployed.selector);
        vm.prank(owner);
        factory.deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_deployYieldModule_RevertsOnlyOwnerInitsToken() public {
        vm.expectRevert(TangemYieldModuleFactory.OnlyOwnerInitsToken.selector);
        vm.prank(otherAccount);
        factory.deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_deployYieldModule_AllowsDeployOnBehalfWithoutToken() public {
        vm.prank(otherAccount);
        address yieldModule = factory.deployYieldModule(owner, address(0), 0);

        assertEq(factory.yieldModules(owner), yieldModule);
    }
}
