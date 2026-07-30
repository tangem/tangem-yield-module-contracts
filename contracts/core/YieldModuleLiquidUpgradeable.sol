// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Requires } from "../common/Requires.sol";
import { FeeAccounting } from "./FeeAccounting.sol";
import { YieldModuleBase } from "./YieldModuleBase.sol";

abstract contract YieldModuleLiquidUpgradeable is YieldModuleBase, FeeAccounting {
    using SafeERC20 for IERC20;
    using Requires for uint;
    using Requires for address;

    /* PROCESSOR FUNCTIONS */

    function enterProtocol(address yieldToken, uint networkFee) external onlyProcessor {
        _enterProtocol(yieldToken, type(uint).max, networkFee); // enter with all funds available
    }

    // emergency function to save user's funds in case protocol or module is compromised
    function exitProtocol(address yieldToken, uint networkFee) external onlyProcessor {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.active, TokenNotActive());

        uint fee = calculateFee(yieldToken, networkFee); // calculate service fee before changing funds in a protocol
        uint amountToExit = type(uint).max; // withdraw all

        uint exitAmount = _pullFromProtocolToOwner(yieldToken, amountToExit);
        _tryProcessFee(yieldToken, fee, false);

        // disable token to avoid abuse by processor
        yieldTokenData.active = false;

        emit ProtocolExited(yieldToken, exitAmount, networkFee);
    }

    function collectServiceFee(address yieldToken) external onlyProcessor {
        uint fee = calculateServiceFee(yieldToken);
        require(fee > 0, NothingToCollect());

        bool success = _tryProcessFee(yieldToken, fee, true);
        require(success, FeeProcessingFailed());
    }

    /* RISK SERVICE FUNCTIONS */

    function softExit(address yieldToken) external onlyProcessor {
        _softExit(yieldToken, type(uint).max);
    }

    function softExit(address yieldToken, uint amount) external onlyProcessor {
        amount.requireNotZero();

        _softExit(yieldToken, amount);
    }

    function suspendToken(address yieldToken) external onlyProcessor {
        _requireEntryAllowed(yieldToken);

        entrySuspended[yieldToken] = true;

        emit EntrySuspensionSet(yieldToken, true);
    }

    function resumeAndEnterProtocol(address yieldToken) external onlyProcessor {
        require(yieldTokensData[yieldToken].active, TokenNotActive());
        require(entrySuspended[yieldToken], NotEntrySuspended());

        entrySuspended[yieldToken] = false;

        if (IERC20(yieldToken).balanceOf(owner) > 0) {
            _enterProtocol(yieldToken, type(uint).max, 0);
        }

        emit EntrySuspensionSet(yieldToken, false);
    }

    /* OWNER FUNCTIONS */

    function initYieldToken(address yieldToken, uint240 maxNetworkFee) external onlyOwnerOrFactory {
        require(!yieldTokensData[yieldToken].initialized, TokenAlreadyInitialized());
        yieldToken.requireNotZero();

        yieldTokensData[yieldToken] = YieldTokenData(true, true, maxNetworkFee);

        address protocolToken = _initProtocolToken(yieldToken);
        protocolToken.requireNotZero();

        protocolTokens[yieldToken] = IERC20(protocolToken);
        isProtocolToken[protocolToken] = true;

        emit YieldTokenInitialized(yieldToken, protocolToken, maxNetworkFee);
    }

    function enterProtocolByOwner(address yieldToken) external onlyOwner {
        _enterProtocol(yieldToken, type(uint).max, 0); // enter with all funds available
    }

    function enterProtocolByOwner(address yieldToken, uint amount) external onlyOwner {
        _enterProtocol(yieldToken, amount, 0);
    }

    function send(address yieldToken, address to, uint amount) external onlyOwner {
        // use withdraw/withdrawAndDeactivate to send to owner to avoid funds being pushed back to protocol
        require(to != owner, SendingToOwner());
        require(yieldTokensData[yieldToken].active, TokenNotActive());
        amount.requireNotZero();

        IERC20 ierc20Token = IERC20(yieldToken);

        uint fee = calculateServiceFee(yieldToken); // calculate service fee before changing funds in a protocol
        uint ownerBalance = ierc20Token.balanceOf(owner);

        uint protocolBal;
        uint pullAmount;
        if (ownerBalance < amount) {
            pullAmount = amount - ownerBalance;

            protocolBal = _protocolBalance(yieldToken);
            require(protocolBal >= pullAmount + fee, InsufficientFunds());

            _pullFromProtocolToOwner(yieldToken, pullAmount);
        }

        ierc20Token.safeTransferFrom(owner, to, amount);

        if (ownerBalance < amount) {
            _processFeeAfterProtocolPull(yieldToken, fee, protocolBal, pullAmount);
        }

        emit SendProcessed(yieldToken, to, amount);
    }

    function withdraw(address yieldToken, uint amount) external onlyOwner {
        require(yieldTokensData[yieldToken].active, TokenNotActive());
        amount.requireNotZero();

        uint protocolBal = _protocolBalance(yieldToken);
        uint fee = _calculateServiceFee(yieldToken, protocolBal); // calculate service fee before changing funds in a protocol

        require(protocolBal >= amount + fee, InsufficientFunds());

        _pullFromProtocolToOwner(yieldToken, amount);

        _processFeeAfterProtocolPull(yieldToken, fee, protocolBal, amount);

        emit WithdrawProcessed(yieldToken, amount);
    }

    function withdrawAndDeactivate(address yieldToken) external onlyOwner {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.active, TokenNotActive());

        uint protocolBal = _protocolBalance(yieldToken);
        // calculate service fee before changing funds in a protocol
        uint fee = _calculateServiceFee(yieldToken, protocolBal);

        // we should still allow to deactivate token even if there is some error
        uint feeToCharge = fee > protocolBal ? protocolBal : fee;
        uint amountToExit = protocolBal - feeToCharge;

        if (amountToExit > 0) {
            _pullFromProtocolToOwner(yieldToken, amountToExit);
        }

        // the whole balance left is charged as fee
        // we can lose debt if the balance were less than the debt due to some error, but we have no means to get it anyway,
        // since not enough funds left, but we'll catch this behaviour with data collection
        _processFeeAfterProtocolPull(yieldToken, feeToCharge, protocolBal, amountToExit);

        // disable token to avoid abuse by processor
        yieldTokenData.active = false;

        emit WithdrawAndDeactivateProcessed(yieldToken, amountToExit);
    }

    function withdrawNonYieldToken(address token) external onlyOwner {
        require(!yieldTokensData[token].active, WithdrawingYieldToken());
        require(!isProtocolToken[token], WithdrawingProtocolToken());
        token.requireNotZero();

        IERC20 ierc20Token = IERC20(token);
        uint balance = ierc20Token.balanceOf(address(this));
        ierc20Token.safeTransfer(owner, balance);

        emit WithdrawNonYieldProcessed(token, balance);
    }

    function withdrawNativeAll(address to) external onlyOwner {
        to.requireNotZero();

        uint amount = address(this).balance;
        if (amount == 0) {
            emit WithdrawNativeProcessed(to, 0);
            return;
        }

        (bool success,) = to.call{ value: amount }("");
        require(success, NativeTransferFailed());

        emit WithdrawNativeProcessed(to, amount);
    }

    // used to reactivate token after exitProtocol and withdrawAndDeactivate
    function reactivateToken(address yieldToken, uint240 maxNetworkFee) external onlyOwner {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.initialized, TokenNotInitialized());
        require(yieldTokenData.active == false, TokenAlreadyActive());

        yieldTokenData.active = true;
        yieldTokenData.maxNetworkFee = maxNetworkFee;

        emit TokenReactivated(yieldToken, maxNetworkFee);
    }

    function setYieldTokenMaxNetworkFee(address yieldToken, uint240 maxNetworkFee) external onlyOwner {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.initialized, TokenNotInitialized());
        require(yieldTokenData.active == true, TokenNotActive());

        yieldTokenData.maxNetworkFee = maxNetworkFee;

        emit TokenMaxNetworkFeeSet(yieldToken, maxNetworkFee);
    }

    /* VIEW FUNCTIONS */

    function protocolBalance(address yieldToken) external view returns (uint) {
        return _protocolBalance(yieldToken);
    }

    function effectiveBalance(address yieldToken) external view returns (uint) {
        uint effectiveProtocolBal = effectiveProtocolBalance(yieldToken);

        return IERC20(yieldToken).balanceOf(owner) + effectiveProtocolBal;
    }

    function effectiveProtocolBalance(address yieldToken) public view returns (uint) {
        uint protocolBalance_ = _protocolBalance(yieldToken);
        uint fee = _calculateServiceFee(yieldToken, protocolBalance_);

        return protocolBalance_ > fee ? (protocolBalance_ - fee) : 0;
    }

    /* INTERNAL FUNCTIONS */

    function _isEntryAllowed(address yieldToken) internal view returns (bool) {
        return yieldTokensData[yieldToken].active && !entrySuspended[yieldToken];
    }

    function _requireEntryAllowed(address yieldToken) internal view {
        require(yieldTokensData[yieldToken].active, TokenNotActive());
        require(!entrySuspended[yieldToken], TokenEntrySuspended());
    }

    /* PRIVATE FUNCTIONS */

    function _enterProtocol(address yieldToken, uint amount, uint networkFee) private {
        _requireEntryAllowed(yieldToken);

        IERC20 ierc20YieldToken = IERC20(yieldToken);

        if (amount == type(uint).max) {
            amount = ierc20YieldToken.balanceOf(owner);
        }

        ierc20YieldToken.safeTransferFrom(owner, address(this), amount);

        // calculate service fee before changing funds in a protocol
        uint fee = calculateFee(yieldToken, networkFee);
        uint amountToEnter = ierc20YieldToken.balanceOf(address(this)); // in case some yield token is stuck in module

        amountToEnter.requireNotZero();
        require(amountToEnter > networkFee, NetworkFeeExceedsAmount());

        _pushToProtocol(yieldToken, amountToEnter);
        _tryProcessFee(yieldToken, fee, true);

        emit ProtocolEntered(yieldToken, amountToEnter, networkFee);
    }

    function _softExit(address yieldToken, uint amount) private {
        require(yieldTokensData[yieldToken].active, TokenNotActive());

        if (!entrySuspended[yieldToken]) {
            entrySuspended[yieldToken] = true;
            emit EntrySuspensionSet(yieldToken, true);
        }

        uint protocolBal = _protocolBalance(yieldToken);
        uint fee = _calculateServiceFee(yieldToken, protocolBal);

        uint available = protocolBal > fee ? protocolBal - fee : 0;
        amount = amount > available ? available : amount;

        if (amount > 0) {
            _pullFromProtocolToOwner(yieldToken, amount);
        }

        _processFeeAfterProtocolPull(yieldToken, fee, protocolBal, amount);

        emit SoftExitTriggered(yieldToken, protocolBal, amount);
    }
}
