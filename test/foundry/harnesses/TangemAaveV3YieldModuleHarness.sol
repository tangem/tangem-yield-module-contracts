// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModule } from "contracts/aave/TangemAaveV3YieldModule.sol";
import { YieldModuleHarness } from "./YieldModuleHarness.sol";

/// Thin wrapper exposing internal state of the yield module for assertions and pre-seeding
/// (via YieldModuleHarness mixin). Deployed as the factory implementation in tests instead of
/// the production contract.
contract TangemAaveV3YieldModuleHarness is TangemAaveV3YieldModule, YieldModuleHarness {
    constructor(
        address pool_,
        address distributor_,
        address yieldProcessor_,
        address factory_,
        address trustedForwarder_,
        address swapExecutionRegistry_
    )
        TangemAaveV3YieldModule(
            pool_,
            distributor_,
            yieldProcessor_,
            factory_,
            trustedForwarder_,
            swapExecutionRegistry_
        )
    { }
}