// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { YieldModuleHarness } from "./YieldModuleHarness.sol";
import { TangemAaveV3YieldModule } from "contracts/aave/TangemAaveV3YieldModule.sol";

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
            pool_, distributor_, yieldProcessor_, factory_, trustedForwarder_, swapExecutionRegistry_
        )
    { }
}
