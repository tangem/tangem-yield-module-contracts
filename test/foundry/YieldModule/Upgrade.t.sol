// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.29;

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { YieldModuleFixture } from "../YieldModuleFixture.sol";
import { YieldModuleGeneralHarness } from "../harnesses/YieldModuleGeneralHarness.sol";
import { YieldModuleHarness } from "../harnesses/YieldModuleHarness.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract UpgradeTest is YieldModuleFixture {
    YieldModuleHarness internal yieldModule;
    YieldModuleGeneralHarness internal newImplementation;

    function setUp() public override {
        super.setUp();
        _registerGeneralImplementation();

        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        newImplementation = new YieldModuleGeneralHarness(
            address(generalPool),
            address(merklDistributor),
            address(processor),
            address(factory),
            address(swapExecutionRegistry),
            address(wrappedNative)
        );

        vm.startPrank(backend);
        factory.pause();
        factory.setImplementation(address(newImplementation));
        vm.stopPrank();
    }

    function test_upgradeToAndCall_UpgradesToNewImplementation() public {
        assertEq(_implementationOf(address(yieldModule)), address(ymGeneralImpl));

        vm.prank(owner);
        yieldModule.upgradeToAndCall(address(newImplementation), "");

        assertEq(_implementationOf(address(yieldModule)), address(newImplementation));
    }

    function test_upgradeToAndCall_Reverts_WhenNotOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeToAndCall_Reverts_WhenImplementationNotAuthorized() public {
        vm.expectRevert(IYieldModule.UnauthorizedImplementation.selector);
        vm.prank(owner);
        yieldModule.upgradeToAndCall(address(ymGeneralImpl), "");
    }

    function test_upgradeToAndCall_EmitsUpgraded() public {
        vm.expectEmit(address(yieldModule));
        emit IERC1967.Upgraded(address(newImplementation));

        vm.prank(owner);
        yieldModule.upgradeToAndCall(address(newImplementation), "");
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }
}
