// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { SwapExecution } from "contracts/extensions/SwapExecution.sol";

abstract contract YieldModuleHarness is SwapExecution {
    function exposed_setFeeDebt(address yieldToken, uint amount) public {
        feeDebts[yieldToken] = amount;
    }

    function exposed_setLatestFeePaymentState(address yieldToken, uint protocolBalance_, uint serviceFeeRate_) public {
        latestFeePaymentStates[yieldToken] = LatestFeePaymentState(protocolBalance_, serviceFeeRate_);
    }
}
