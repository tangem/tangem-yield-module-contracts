// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { TangemAaveV3YieldModuleBase } from "./base/TangemAaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";
import { PRECISION } from "contracts/resources/Constants.sol";

contract DeploymentTest is TangemAaveV3YieldModuleBase {
    function test_deployYieldModule_SetsOwner() public {
        TangemAaveV3YieldModuleHarness yieldModule = _deployYieldModule(owner, address(0), 0);

        assertEq(yieldModule.owner(), owner);
    }

    function test_deployYieldModule_InitializesYieldToken() public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);

        (bool initialized, bool active, uint240 maxNetworkFee) =
            yieldModule.yieldTokensData(address(yieldToken));
        assertTrue(initialized);
        assertTrue(active);
        assertEq(maxNetworkFee, DEFAULT_MAX_NETWORK_FEE);

        assertEq(address(yieldModule.protocolTokens(address(yieldToken))), address(protocolToken));
        assertTrue(yieldModule.isProtocolToken(address(protocolToken)));
    }

    function test_deployYieldModule_EmitsYieldTokenInitialized() public {
        address expectedYieldModule = factory.calculateYieldModuleAddress(owner);

        vm.expectEmit(expectedYieldModule);
        emit IYieldModule.YieldTokenInitialized(
            address(yieldToken),
            address(protocolToken),
            DEFAULT_MAX_NETWORK_FEE
        );

        _deployYieldModule(owner, address(yieldToken), DEFAULT_MAX_NETWORK_FEE);
    }
}

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

contract SetYieldTokenMaxNetworkFeeTest is TangemAaveV3YieldModuleBase {
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

contract ServiceFeeViewsTest is TangemAaveV3YieldModuleBase {
    uint internal constant INITIAL_OWNER_BALANCE = 200_000e6;

    function test_calculateServiceFee_AfterRevenue() public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        uint revenue = 10_000e6;

        _generateRevenue(address(yieldModule), revenue);

        uint expectedFee = revenue * SERVICE_FEE_RATE / PRECISION;
        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), expectedFee);
    }

    // example of pre-seeding internal state through the harness
    function test_calculateServiceFee_IncludesPreseededFeeDebt() public {
        TangemAaveV3YieldModuleHarness yieldModule =
            _deployEnteredYieldModule(owner, INITIAL_OWNER_BALANCE);
        uint feeDebt = 700e6;

        yieldModule.exposed_setFeeDebt(address(yieldToken), feeDebt);

        assertEq(yieldModule.calculateServiceFee(address(yieldToken)), feeDebt);
    }
}
