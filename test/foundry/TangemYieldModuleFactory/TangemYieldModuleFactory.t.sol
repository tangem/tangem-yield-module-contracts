// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { TangemYieldModuleFactory } from "contracts/infra/TangemYieldModuleFactory.sol";

contract TangemYieldModuleFactoryTest is YieldModuleFixture {
    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();
    }

    function test_deployYieldModule_SetsOwner() public {
        YieldModuleHarness yieldModule = _deployYieldModule(owner, address(0), 0);

        assertEq(yieldModule.owner(), owner);
    }

    function test_deployYieldModule_EmitsYieldModuleDeployed() public {
        address expectedYieldModule = factory.calculateYieldModuleAddress(owner);

        vm.expectEmit(true, true, false, false, address(factory));
        emit TangemYieldModuleFactory.YieldModuleDeployed(owner, expectedYieldModule);

        _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_deployYieldModule_Reverts_WhenModuleAlreadyDeployed() public {
        _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        vm.expectRevert(TangemYieldModuleFactory.ModuleAlreadyDeployed.selector);
        vm.prank(owner);
        factory.deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }

    function test_deployYieldModule_Reverts_WhenNonOwnerInitsToken() public {
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
