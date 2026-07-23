// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MerklIncentives } from "contracts/merkl/MerklIncentives.sol";

abstract contract YieldModuleHarness is MerklIncentives {
    function exposed_setFeeDebt(address yieldToken, uint amount) public {
        feeDebts[yieldToken] = amount;
    }

    function exposed_setLatestFeePaymentState(address yieldToken, uint protocolBalance_, uint serviceFeeRate_) public {
        latestFeePaymentStates[yieldToken] = LatestFeePaymentState(protocolBalance_, serviceFeeRate_);
    }

    function exposed_setYieldTokenByProtocolToken(address protocolToken, address yieldToken) public {
        yieldTokenByProtocolToken[protocolToken] = yieldToken;
    }

    function exposed_resolveYieldToken(address protocolToken) public returns (address) {
        return _resolveYieldToken(protocolToken);
    }
}
