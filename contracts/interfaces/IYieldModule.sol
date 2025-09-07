// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;


interface IYieldModule {
    event YieldTokenInitialized(address yieldToken, address protocolToken, uint maxNetworkFee);
    event ProtocolEntered(address yieldToken, uint amount, uint networkFee);
    event ProtocolExited(address yieldToken, uint amount, uint networkFee);
    event FeePaymentProcessed(address yieldToken, uint amount, address receiver);
    event FeePaymentFailed(address yieldToken, uint serviceFeeDebt); // TODO: add reason?
    event LatestFeePaymentStateUpdated(address yieldToken, uint protocolBalance, uint serviceFeeRate);
    event SendProcessed(address yieldToken, address to, uint amount);
    event WithdrawAndDeactivateProcessed(address yieldToken, uint amount);
    event WithdrawNonYieldProcessed(address token, uint amount);
    event TokenReactivated(address yieldToken, uint maxNetworkFee);
    event TokenMaxNetworkFeeSet(address yieldToken, uint240 maxNetworkFee);

    function initialize(address owner) external;

    function initYieldToken(address yieldToken, uint240 maxNetworkFee) external;

    function enterProtocol(address yieldToken, uint networkFee) external;

    function exitProtocol(address yieldToken, uint networkFee) external;

    function collectServiceFee(address yieldToken) external;

    function send(address yieldToken, address to, uint amount) external;

    function withdrawAndDeactivate(address yieldToken) external;

    function withdrawNonYieldToken(address token) external;

    function reactivateToken(address yieldToken, uint240 maxNetworkFee) external;

    function setYieldTokenMaxNetworkFee(address yieldToken, uint240 maxNetworkFee) external;

    function protocolBalance(address yieldToken) external view returns (uint);
    
    function effectiveBalance(address yieldToken) external view returns (uint);

    function calculateServiceFee(address yieldToken) external view returns (uint);
}