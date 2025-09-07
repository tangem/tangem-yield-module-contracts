// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "../interfaces/IYieldProcessor.sol";
import "../interfaces/IYieldModule.sol";
import "../resources/Constants.sol";

contract TangemYieldProcessor is IYieldProcessor, AccessControlEnumerable, Pausable {
    using Arrays for uint[];

    bytes32 public constant PROTOCOL_ENTERER_ROLE = keccak256("PROTOCOL_ENTERER_ROLE");
    bytes32 public constant PROTOCOL_EXITER_ROLE = keccak256("PROTOCOL_EXITER_ROLE");
    bytes32 public constant SERVICE_FEE_COLLECTOR_ROLE = keccak256("SERVICE_FEE_COLLECTOR_ROLE");
    bytes32 public constant PROPERTY_SETTER_ROLE = keccak256("PROPERTY_SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public feeReceiver;
    uint public serviceFeeRate; // rate is specified in basis points (0.01 %)

    event ProtocolEntered(address yieldModule);
    event ProtocolExited(address yieldModule);
    event ServiceFeeCollected(address yieldModule);
    event FeeReceiverSet(address paymentReceiver);
    event FeeRateSet(uint feeRate);

    constructor(
        address feeReceiver_,
        uint serviceFeeRate_
    ) {
        feeReceiver = feeReceiver_;
        _setServiceFeeRate(serviceFeeRate_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function enterProtocol(
        address yieldModule,
        address yieldToken,
        uint networkFee
    ) external whenNotPaused onlyRole(PROTOCOL_ENTERER_ROLE) {
        IYieldModule(yieldModule).enterProtocol(yieldToken, networkFee);

        emit ProtocolEntered(yieldModule);
    }

    function exitProtocol(
        address yieldModule,
        address yieldToken,
        uint networkFee
    ) external whenNotPaused onlyRole(PROTOCOL_EXITER_ROLE) {
        IYieldModule(yieldModule).exitProtocol(yieldToken, networkFee);

        emit ProtocolExited(yieldModule);
    }

    function collectServiceFee(address yieldModule, address yieldToken)
        external
        whenNotPaused
        onlyRole(SERVICE_FEE_COLLECTOR_ROLE)
    {
        IYieldModule(yieldModule).collectServiceFee(yieldToken);

        emit ServiceFeeCollected(yieldModule);
    }

    function setFeeReceiver(address feeReceiver_) external onlyRole(PROPERTY_SETTER_ROLE) {
        feeReceiver = feeReceiver_;

        emit FeeReceiverSet(feeReceiver_);
    }

    function setServiceFeeRate(uint feeRate_) external onlyRole(PROPERTY_SETTER_ROLE) {
        _setServiceFeeRate(feeRate_);

        emit FeeRateSet(feeRate_);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _setServiceFeeRate(uint serviceFeeRate_) private {
        require(serviceFeeRate_ <= PRECISION, "YieldProcessor: fee cannot be > 100%");

        serviceFeeRate = serviceFeeRate_;
    }
}