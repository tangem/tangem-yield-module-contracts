// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IYieldModule.sol";
import "../interfaces/IYieldFactory.sol";
import "../interfaces/IYieldProcessor.sol";
import "../interfaces/ISwapExecutionRegistry.sol";
import "../resources/Constants.sol";
import "../common/Requires.sol";

abstract contract YieldModuleLiquidUpgradeable is
    Initializable,
    ERC2771ContextUpgradeable,
    IYieldModule,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
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

    struct SwapContext {
        IERC20 tokenIn;
        address tokenInAddr;
        address spenderEffective;
        uint amountIn;
        uint feeIn;
        bool protocolTouched;
    }

    IYieldProcessor public immutable processor;
    IYieldFactory public immutable factory;
    ISwapExecutionRegistry public immutable swapExecutionRegistry;
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
    constructor(address processor_, address factory_, address trustedForwarder_, address swapExecutionRegistry_)
        ERC2771ContextUpgradeable(trustedForwarder_)
    {
        processor = IYieldProcessor(processor_);
        factory = IYieldFactory(factory_);
        swapExecutionRegistry = ISwapExecutionRegistry(swapExecutionRegistry_);
    }

    receive() external payable {}

    function __YieldModule_init(address owner_) internal onlyInitializing {
        __ReentrancyGuard_init();
        __YieldModule_init_unchained(owner_);
    }

    function __YieldModule_init_unchained(address owner_) internal onlyInitializing {
        owner = owner_;
    }

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

        if (ownerBalance < amount) { // no need to process fee if the protocol balance hasn't changed
            if (protocolBal == pullAmount + fee) { // avoid protocol rounding errors on sending all available funds
                fee = _protocolBalance(yieldToken);
            } 
            _tryProcessFee(yieldToken, fee, true);
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

        if (protocolBal == amount + fee) { // avoid protocol rounding errors on withdrawing all available funds
            fee = _protocolBalance(yieldToken);
        } 
        _tryProcessFee(yieldToken, fee, true);

        emit WithdrawProcessed(yieldToken, amount);
    }

    function withdrawAndDeactivate(address yieldToken) external onlyOwner {
        YieldTokenData storage yieldTokenData = yieldTokensData[yieldToken];
        require(yieldTokenData.active, TokenNotActive());

        uint protocolBal = _protocolBalance(yieldToken);
        // calculate service fee before changing funds in a protocol
        uint fee = _calculateServiceFee(yieldToken, protocolBal);

        uint amountToExit = protocolBal >= fee ? protocolBal - fee : 0; // we should still allow to deactivate token even if there is some error
        
        if (amountToExit > 0) {
            _pullFromProtocolToOwner(yieldToken, amountToExit);
        }

        // get protocol balance again to avoid protocol rounding errors
        // we can lose debt if the balance were less than the debt due to some error, but we have no means to get it anyway,
        // since not enough funds left, but we'll catch this behaviour with data collection
        _tryProcessFee(yieldToken, _protocolBalance(yieldToken), true); 

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

        (bool success, ) = to.call{value: amount}("");
        require(success, NativeTransferFailed());

        emit WithdrawNativeProcessed(to, amount);
    }

    function enterProtocolByOwner(address yieldToken) external onlyOwner {
        _enterProtocol(yieldToken, type(uint).max, 0); // enter with all funds available
    }

    function enterProtocolByOwner(address yieldToken, uint amount) external onlyOwner {
        _enterProtocol(yieldToken, amount, 0);
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

    function swap(
        address tokenIn,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    )
        external
        payable
        onlyOwner
        nonReentrant
    {
        SwapContext memory context = _prepareSwap(tokenIn, amountIn, target, spender, data);

        _callProvider(target, data);

        _finalizeSwap(context);

        emit SwapInitiated(
            tokenIn,
            amountIn,
            target,
            context.spenderEffective,
            msg.value,
            keccak256(data)
        );
    }

    function swapAndReceive(
        address tokenIn,
        address tokenOut,
        address to,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    )
        external
        payable
        onlyOwner
        nonReentrant
    {
        tokenOut.requireNotZero();
        require(tokenOut != tokenIn, TokenInEqualsTokenOut());
        require(!isProtocolToken[tokenOut], WithdrawingProtocolToken());

        uint outBefore = IERC20(tokenOut).balanceOf(address(this));

        SwapContext memory context = _prepareSwap(tokenIn, amountIn, target, spender, data);

        _callProvider(target, data);

        _finalizeSwap(context);

        uint outAfter = IERC20(tokenOut).balanceOf(address(this));
        uint received = (outAfter > outBefore) ? (outAfter - outBefore) : 0;
        require(received > 0, SwapPayoutNotReceived());

        emit SwapAndReceiveInitiated(
            tokenIn,
            tokenOut,
            to,
            amountIn,
            target,
            context.spenderEffective,
            msg.value,
            keccak256(data)
        );

        bool deposited;
        if (yieldTokensData[tokenOut].active) {
            uint feeOut = calculateServiceFee(tokenOut);

            _pushToProtocol(tokenOut, outAfter);
            _tryProcessFee(tokenOut, feeOut, true);

            deposited = true;
        } else {
            to.requireNotZero();
            require(to != address(this), SendingToThis());

            IERC20(tokenOut).safeTransfer(to, received);
            deposited = false;
        }

        emit SwapAndReceiveCompleted(tokenOut, to, received, deposited);
    }

    /* VIEW FUNCTIONS */

    function protocolBalance(address yieldToken) external view returns (uint) {
        return _protocolBalance(yieldToken);
    }

    function effectiveProtocolBalance(address yieldToken) external view returns (uint) {
        uint protocolBalance_ = _protocolBalance(yieldToken);
        uint fee = _calculateServiceFee(yieldToken, protocolBalance_);

        return protocolBalance_ > fee ? (protocolBalance_ - fee) : 0;
    }

    function effectiveBalance(address yieldToken) external view returns (uint) {
        uint protocolBalance_ = _protocolBalance(yieldToken);
        uint fee = _calculateServiceFee(yieldToken, protocolBalance_);
        uint effectiveProtocolBal = protocolBalance_ > fee ? (protocolBalance_ - fee) : 0;

        return IERC20(yieldToken).balanceOf(owner) + effectiveProtocolBal;
    }

    function calculateFee(address yieldToken, uint networkFee) public view returns (uint) {
        require(networkFee <= yieldTokensData[yieldToken].maxNetworkFee, NetworkFeeExceedsMax());

        return calculateServiceFee(yieldToken) + networkFee;
    }

    function calculateServiceFee(address yieldToken) public view returns (uint) {
        return _calculateServiceFee(yieldToken, _protocolBalance(yieldToken));
    }

    /* PRIVATE AND INTERNAL FUNCTIONS */

    function _tryProcessFee(address yieldToken, uint amount, bool useProtocolToken) private returns (bool success) {
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
            _processFeePaymentSuccess(yieldToken, transferAmount, feeReceiver);
            if (debt > 0) {
                feeDebts[yieldToken] = debt;
            }
        } else { // shouldn't happen with proper fee receiver
            _processFeePaymentFailure(yieldToken, amount);
        }

        return transferSuccess;
    }

    function _enterProtocol(address yieldToken, uint amount, uint networkFee) private {
        require(yieldTokensData[yieldToken].active, TokenNotActive());

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

        // even if balance dropped, outstanding debt must still be collected.
        if (protocolBalance_ <= latestFeePaymentProtocolBalance) return feeDebts[yieldToken];

        uint revenue;
        unchecked { // checked with last if
            revenue = protocolBalance_ - latestFeePaymentProtocolBalance;
        }
        uint currentServiceFee = revenue * latestFeePaymentServiceFeeRate / PRECISION;

        return currentServiceFee + feeDebts[yieldToken];
    }

    function _protocolBalance(address yieldToken) internal view returns (uint) {
        return protocolTokens[yieldToken].balanceOf(address(this));
    }

    function _initProtocolToken(address yieldToken) internal virtual returns (address);

    function _pushToProtocol(address yieldToken, uint amount) internal virtual;

    function _pullFromProtocolToOwner(address yieldToken, uint amount) internal virtual returns (uint);

    function _pullFromProtocolToModule(address yieldToken, uint amount) internal virtual returns (uint);

    function _prepareSwap(
        address tokenIn,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    )
        internal
        returns (SwapContext memory context)
    {
        require(yieldTokensData[tokenIn].active, TokenNotActive());

        amountIn.requireNotZero();
        target.requireNotZero();
        require(target.code.length > 0, TargetHasNoCode());
        require(data.length >= 4, DataTooShort());

        address spenderEffective = (spender == address(0)) ? target : spender;

        require(swapExecutionRegistry.allowedTargets(target), TargetNotAllowed());
        require(swapExecutionRegistry.allowedSpenders(spenderEffective), SpenderNotAllowed());

        uint feeIn = calculateServiceFee(tokenIn);

        IERC20 tokenInErc20 = IERC20(tokenIn);

        // use any stuck funds on the module
        uint moduleBal = tokenInErc20.balanceOf(address(this));
        uint collected = moduleBal >= amountIn ? amountIn : moduleBal;
        uint needed = amountIn - collected;

        // take from owner if needed
        bool protocolTouched;
        if (needed > 0) {
            uint ownerBal = tokenInErc20.balanceOf(owner);
            uint fromOwner = ownerBal >= needed ? needed : ownerBal;
            if (fromOwner > 0) {
                tokenInErc20.safeTransferFrom(owner, address(this), fromOwner);
            }
            needed -= fromOwner;
        }

        // pull from protocol directly to module if still needed
        if (needed > 0) {
            uint protocolBal = _protocolBalance(tokenIn);

            require(protocolBal >= needed + feeIn, InsufficientFunds());
            if (protocolBal == needed + feeIn) { // avoid protocol rounding errors on withdrawing all available funds
                feeIn = type(uint).max; // use whole balance left as fee
            }

            _pullFromProtocolToModule(tokenIn, needed);
            protocolTouched = true;
        }

        tokenInErc20.forceApprove(spenderEffective, amountIn);

        context = SwapContext({
            tokenIn: tokenInErc20,
            tokenInAddr: tokenIn,
            spenderEffective: spenderEffective,
            amountIn: amountIn,
            feeIn: feeIn,
            protocolTouched: protocolTouched
        });
    }

    function _callProvider(address target, bytes calldata data) internal {
        (bool success, bytes memory ret) = target.call{value: msg.value}(data);
        if (!success) {
            if (ret.length > 0) {
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
            revert ProviderCallFailed();
        }
    }

    function _finalizeSwap(SwapContext memory context) internal {
        context.tokenIn.forceApprove(context.spenderEffective, 0);

        // process fee before handling residue to avoid inflating fee when feeIn == type(uint).max
        if (context.protocolTouched) {
            address tokenIn = context.tokenInAddr;
            uint feeIn = context.feeIn == type(uint).max ? _protocolBalance(tokenIn) : context.feeIn;

            _tryProcessFee(tokenIn, feeIn, true);
        }

        // send any remaining tokenIn (swap dust, stuck funds, or attacker donations) to owner
        uint residue = context.tokenIn.balanceOf(address(this));
        if (residue > 0) {
            context.tokenIn.safeTransfer(owner, residue);
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
        view
    {
        require(factory.isValidImplementation(newImplementation), UnauthorizedImplementation());
    }
}