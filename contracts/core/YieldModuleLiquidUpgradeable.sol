// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IYieldModule.sol";
import "../interfaces/IYieldFactory.sol";
import "../interfaces/IYieldProcessor.sol";
import "../resources/Constants.sol";
import "../common/Requires.sol";

abstract contract YieldModuleLiquidUpgradeable is
    Initializable,
    ERC2771ContextUpgradeable,
    IYieldModule,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Requires for uint;
    using Requires for address;

    struct YieldTokenData {
        bool initialized;
        bool active;
        uint240 maxNetworkFee;
    }

    struct LatestFeePaymentState {
        uint protocolBalance;
        uint serviceFeeRate;
    }

    IYieldProcessor public immutable processor;
    IYieldFactory public immutable factory;
    address public owner;

    // yield token => yield token data
    mapping(address => YieldTokenData) public yieldTokensData;
    // yield token => protocol token
    mapping(address => IERC20) public protocolTokens;
    // yield token => latest fee payment state
    mapping(address => LatestFeePaymentState) public latestFeePaymentStates;
    // yield token => fee debt
    mapping(address => uint) public feeDebts;
    mapping(address => bool) public isProtocolToken;

    modifier onlyOwner {
        require(_msgSender() == owner, OnlyOwner());
        _;
    }

    modifier onlyOwnerOrFactory {
        address msgSender = _msgSender();
        require(msgSender == owner || msgSender == address(factory), OnlyOwnerOrFactory());
        _;
    }

    modifier onlyProcessor {
        require(_msgSender() == address(processor), OnlyProcessor());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address processor_, address factory_, address trustedForwarder)
        ERC2771ContextUpgradeable(trustedForwarder)
    {
        processor = IYieldProcessor(processor_);
        factory = IYieldFactory(factory_);
    }

    function __YieldModule_init(address owner_) internal onlyInitializing {
        __YieldModule_init_unchained(owner_);
    }

    function __YieldModule_init_unchained(address owner_) internal onlyInitializing {
        owner = owner_;
    }

    /* PROCESSOR FUNCTIONS */

    function enterProtocol(address yieldToken, uint networkFee) external onlyProcessor {
        _enterProtocol(yieldToken, networkFee);
    }

    // emergency function to save user's funds in case protocol or module is compromised
    function exitProtocol(address yieldToken, uint networkFee) external onlyProcessor {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.active, TokenNotActive());

        // calculate service fee before changing funds in a protocol
        uint fee = calculateFee(yieldToken, networkFee);
        uint amountToExit = type(uint256).max; // withdraw all
        
        uint exitAmount = _pullFromProtocol(yieldToken, amountToExit);
        _tryProcessFee(yieldToken, fee, false);

        // disable token to avoid abuse by processor
        yieldTokenData.active = false;

        emit ProtocolExited(yieldToken, exitAmount, networkFee);
    }

    function collectServiceFee(address yieldToken) external onlyProcessor {
        bool success = _tryProcessFee(yieldToken, calculateServiceFee(yieldToken), true);

        require(success, FeeProcessingFailed());
    }

    /* OWNER FUNCTIONS */

    function initYieldToken(address yieldToken, uint240 maxNetworkFee) external onlyOwnerOrFactory {
        require(!yieldTokensData[yieldToken].initialized, TokenAlreadyInitialized());
        yieldToken.requireNotZero();

        yieldTokensData[yieldToken] = YieldTokenData(true, true, maxNetworkFee);
        
        address protocolToken = _initProtocolToken(yieldToken);
        protocolTokens[yieldToken] = IERC20(protocolToken);
        isProtocolToken[protocolToken] = true;

        emit YieldTokenInitialized(yieldToken, protocolToken, maxNetworkFee);
    }
    
    function send(address yieldToken, address to, uint amount) external onlyOwner {
        require(to != owner, SendingToOwner()); // use withdrawAndDeactivate to send to owner to avoid funds being pushed back to protocol
        require(yieldTokensData[yieldToken].active, TokenInactive());
        amount.requireNotZero();

        IERC20 ierc20Token = IERC20(yieldToken);

        uint fee = calculateServiceFee(yieldToken);
        uint ownerBalance = ierc20Token.balanceOf(owner);

        if (ownerBalance < amount) {
            _pullFromProtocol(yieldToken, amount - ownerBalance);
        }

        ierc20Token.safeTransferFrom(owner, to, amount);

        if (ownerBalance < amount) { // no need to process fee if the protocol balance hasn't changed
            _tryProcessFee(yieldToken, fee, true);
        }

        emit SendProcessed(yieldToken, to, amount);
    }

    function withdrawAndDeactivate(address yieldToken) external onlyOwner {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.active, TokenNotActive());

        // calculate service fee before changing funds in a protocol
        uint fee = calculateServiceFee(yieldToken);
        uint amountToExit = _protocolBalance(yieldToken) - fee;
        
        _pullFromProtocol(yieldToken, amountToExit);
        _tryProcessFee(yieldToken, _protocolBalance(yieldToken), true); // get protocol balance again to extract all funds, because the amount left can grow a bit after pull

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

    function enterProtocolByOwner(address yieldToken) external onlyOwner {
        _enterProtocol(yieldToken, 0);
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
        uint protocolBalance_ = _protocolBalance(yieldToken);

        return IERC20(yieldToken).balanceOf(owner) +
            protocolBalance_ -
            _calculateServiceFee(yieldToken, protocolBalance_);
    }

    function calculateFee(address yieldToken, uint networkFee) public view returns (uint) {
        require(networkFee <= yieldTokensData[yieldToken].maxNetworkFee, NetworkFeeExceedsMax());

        return calculateServiceFee(yieldToken) + networkFee;
    }

    function calculateServiceFee(address yieldToken) public view returns (uint) {
        return _calculateServiceFee(yieldToken, _protocolBalance(yieldToken)) + feeDebts[yieldToken];
    }

    /* PRIVATE AND INTERNAL FUNCTIONS */

    function _tryProcessFee(address yieldToken, uint amount, bool useProtocolToken) private returns (bool success) {
        if (amount == 0) {
            _processFeePaymentFailure(yieldToken, amount);
            return false;
        }


        uint balance;
        if (useProtocolToken) {
            balance = _protocolBalance(yieldToken);
        } else {
            balance = IERC20(yieldToken).balanceOf(owner);
        }

        if (amount > balance) {
            _processFeePaymentFailure(yieldToken, amount);
            return false;
        }

        address feeReceiver = processor.feeReceiver();
        bool transferSuccess;
        if (useProtocolToken) {
            transferSuccess = protocolTokens[yieldToken].trySafeTransfer(feeReceiver, amount);
        } else {
            transferSuccess = IERC20(yieldToken).trySafeTransferFrom(owner, feeReceiver, amount);
        }

        if (transferSuccess) {
            _processFeePaymentSuccess(yieldToken, amount, feeReceiver);
        } else { // shouldn't happen with proper fee receiver
            _processFeePaymentFailure(yieldToken, amount);
        }

        return transferSuccess;
    }

    function _enterProtocol(address yieldToken, uint networkFee) private {
        require(yieldTokensData[yieldToken].active, TokenNotActive());

        IERC20 ierc20YieldToken = IERC20(yieldToken);
        uint ownerBalance = ierc20YieldToken.balanceOf(owner);
        if (ownerBalance > 0) {
            ierc20YieldToken.safeTransferFrom(owner, address(this), ownerBalance);
        }

        // calculate service fee before changing funds in a protocol
        uint fee = calculateFee(yieldToken, networkFee);
        uint amountToEnter = ierc20YieldToken.balanceOf(address(this));

        amountToEnter.requireNotZero();
        require(amountToEnter > networkFee, NetworkFeeExceedsAmount());
        
        _pushToProtocol(yieldToken, amountToEnter);
        _tryProcessFee(yieldToken, fee, true);

        emit ProtocolEntered(yieldToken, amountToEnter, networkFee);
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

    function _calculateServiceFee(address yieldToken, uint protocolBalance_) private view returns (uint) {
        LatestFeePaymentState storage latestFeePaymentState = latestFeePaymentStates[yieldToken];
        uint latestFeePaymentProtocolBalance = latestFeePaymentState.protocolBalance;
        uint latestFeePaymentServiceFeeRate = latestFeePaymentState.serviceFeeRate;

        if (protocolBalance_ <= latestFeePaymentProtocolBalance) return 0;

        uint revenue;
        unchecked { // checked with last if
            revenue = protocolBalance_ - latestFeePaymentProtocolBalance;
        }

        return revenue * latestFeePaymentServiceFeeRate / PRECISION;
    }

    function _protocolBalance(address yieldToken) internal view returns (uint) {
        return protocolTokens[yieldToken].balanceOf(address(this));
    }

    function _initProtocolToken(address yieldToken) internal virtual returns (address);

    function _pushToProtocol(address yieldToken, uint amount) internal virtual;

    function _pullFromProtocol(address yieldToken, uint amount) internal virtual returns (uint);

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
        view
    {
        require(factory.isValidImplementation(newImplementation), UnauthorizedImplementation());
    }
}