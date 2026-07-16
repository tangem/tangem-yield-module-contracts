// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "./AaveV3YieldModuleBase.sol";

import { TangemAaveV3YieldModule } from "contracts/aave/TangemAaveV3YieldModule.sol";
import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract UpgradeTest is AaveV3YieldModuleBase {
    address internal constant NEW_FORWARDER = address(0);

    TangemAaveV3YieldModuleHarness internal yieldModule;
    TangemAaveV3YieldModule internal newImplementation;

    function setUp() public override {
        super.setUp();

        yieldModule = _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        newImplementation = new TangemAaveV3YieldModule(
            address(pool),
            address(merklDistributor),
            address(processor),
            address(factory),
            NEW_FORWARDER,
            address(swapExecutionRegistry)
        );

        vm.startPrank(backend);
        factory.pause();
        factory.setImplementation(address(newImplementation));
        vm.stopPrank();
    }

    function test_upgradeToAndCall_UpgradesToNewImplementation() public {
        assertEq(yieldModule.trustedForwarder(), address(forwarder));

        vm.prank(owner);
        yieldModule.upgradeToAndCall(address(newImplementation), "");

        assertEq(yieldModule.trustedForwarder(), NEW_FORWARDER);
    }

    function test_upgradeToAndCall_RevertsOnlyOwner() public {
        vm.expectRevert(IYieldModule.OnlyOwner.selector);
        vm.prank(otherAccount);
        yieldModule.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeToAndCall_EmitsUpgraded() public {
        vm.expectEmit(address(yieldModule));
        emit IERC1967.Upgraded(address(newImplementation));

        vm.prank(owner);
        yieldModule.upgradeToAndCall(address(newImplementation), "");
    }
}
