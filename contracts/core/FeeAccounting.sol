// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { PRECISION } from "../common/Constants.sol";
import { YieldModuleBase } from "./YieldModuleBase.sol";

abstract contract FeeAccounting is YieldModuleBase {
    using SafeERC20 for IERC20;

    function calculateFee(address yieldToken, uint networkFee) public view returns (uint) {
        require(networkFee <= yieldTokensData[yieldToken].maxNetworkFee, NetworkFeeExceedsMax());

        return calculateServiceFee(yieldToken) + networkFee;
    }

    function calculateServiceFee(address yieldToken) public view returns (uint) {
        return _calculateServiceFee(yieldToken, _protocolBalance(yieldToken));
    }

    function _tryProcessFee(address yieldToken, uint amount, bool useProtocolToken) internal returns (bool success) {
        if (amount == 0) {
            _processFeePaymentSuccess(yieldToken, 0, processor.feeReceiver());
            return true;
        }

        uint balance;
        if (useProtocolToken) {
            balance = _protocolBalance(yieldToken);
        } else {
            balance = IERC20(yieldToken).balanceOf(owner);
        }

        uint transferAmount = amount > balance ? balance : amount;
        uint debt = amount - transferAmount;

        if (transferAmount == 0) {
            _processFeePaymentFailure(yieldToken, amount);
            return false;
        }

        address feeReceiver = processor.feeReceiver();
        bool transferSuccess;
        if (useProtocolToken) {
            transferSuccess = protocolTokens[yieldToken].trySafeTransfer(feeReceiver, transferAmount);
        } else {
            transferSuccess = IERC20(yieldToken).trySafeTransferFrom(owner, feeReceiver, transferAmount);
        }

        if (transferSuccess) {
            if (debt > 0) {
                feeDebts[yieldToken] = debt;
                _updateLatestFeePaymentState(yieldToken);
                emit FeePaymentPartial(yieldToken, transferAmount, debt, feeReceiver);
            } else {
                _processFeePaymentSuccess(yieldToken, transferAmount, feeReceiver);
            }
        } else {
            // shouldn't happen with proper fee receiver
            _processFeePaymentFailure(yieldToken, amount);
        }

        return transferSuccess;
    }

    function _increaseProtocolBalanceWithoutFee(address token, uint amount) internal {
        LatestFeePaymentState storage latestFeePaymentState = latestFeePaymentStates[token];
        uint newFeeCheckpoint = latestFeePaymentState.protocolBalance + amount;

        require(newFeeCheckpoint <= _protocolBalance(token), FeeCheckpointExceedsBalance());

        latestFeePaymentState.protocolBalance = newFeeCheckpoint;

        emit LatestFeePaymentStateUpdated(token, newFeeCheckpoint, latestFeePaymentState.serviceFeeRate);
    }

    function _calculateServiceFee(address yieldToken, uint protocolBalance_) internal view returns (uint) {
        LatestFeePaymentState storage latestFeePaymentState = latestFeePaymentStates[yieldToken];
        uint latestFeePaymentProtocolBalance = latestFeePaymentState.protocolBalance;
        uint latestFeePaymentServiceFeeRate = latestFeePaymentState.serviceFeeRate;

        // even if balance dropped, outstanding debt must still be collected.
        if (protocolBalance_ <= latestFeePaymentProtocolBalance) return feeDebts[yieldToken];

        uint revenue;
        unchecked { // checked with last if
            revenue = protocolBalance_ - latestFeePaymentProtocolBalance;
        }
        uint currentServiceFee = revenue * latestFeePaymentServiceFeeRate / PRECISION;

        return currentServiceFee + feeDebts[yieldToken];
    }

    function _processFeePaymentSuccess(address token, uint amount, address receiver) private {
        feeDebts[token] = 0;
        _updateLatestFeePaymentState(token);

        emit FeePaymentProcessed(token, amount, receiver);
    }

    function _processFeePaymentFailure(address token, uint amount) private {
        feeDebts[token] = amount;
        _updateLatestFeePaymentState(token);

        emit FeePaymentFailed(token, amount);
    }

    function _updateLatestFeePaymentState(address token) private {
        uint protocolBalance_ = _protocolBalance(token);
        uint serviceFeeRate = processor.serviceFeeRate();
        latestFeePaymentStates[token] = LatestFeePaymentState(protocolBalance_, serviceFeeRate);

        emit LatestFeePaymentStateUpdated(token, protocolBalance_, serviceFeeRate);
    }
}
