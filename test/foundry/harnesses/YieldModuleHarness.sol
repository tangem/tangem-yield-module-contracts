// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MerklIncentives } from "contracts/merkl/MerklIncentives.sol";

/// Abstract harness mixin exposing internal state of the yield module for assertions and
/// pre-seeding. Inherited by all concrete harness variants (general, AAVE, etc.) to avoid
/// duplicating the exposed_* methods.
abstract contract YieldModuleHarness is MerklIncentives {
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

}
