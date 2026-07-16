// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModuleHarness } from "../harnesses/TangemAaveV3YieldModuleHarness.sol";
import { AaveV3YieldModuleBase } from "./AaveV3YieldModuleBase.sol";

import { IYieldModule } from "contracts/interfaces/IYieldModule.sol";

contract TangemAaveV3YieldModuleTest is AaveV3YieldModuleBase {
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
