// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { TangemAaveV3YieldModule } from "contracts/aave/TangemAaveV3YieldModule.sol";

/// Thin wrapper exposing internal state of the yield module for assertions and pre-seeding.
/// Deployed as the factory implementation in tests instead of the production contract.
contract TangemAaveV3YieldModuleHarness is TangemAaveV3YieldModule {
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

    /* GETTERS */

    function exposed_protocolBalance(address yieldToken) public view returns (uint) {
        return _protocolBalance(yieldToken);
    }

    /* SETTERS */

    function exposed_setFeeDebt(address yieldToken, uint amount) public {
        feeDebts[yieldToken] = amount;
    }

    function exposed_setLatestFeePaymentState(
        address yieldToken,
        uint protocolBalance_,
        uint serviceFeeRate_
    ) public {
        latestFeePaymentStates[yieldToken] =
            LatestFeePaymentState(protocolBalance_, serviceFeeRate_);
    }

    function exposed_setYieldTokenActive(address yieldToken, bool active) public {
        yieldTokensData[yieldToken].active = active;
    }
}
