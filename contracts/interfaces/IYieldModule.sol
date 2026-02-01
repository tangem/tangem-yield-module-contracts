// SPDX-License-Identifier: MIT
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
    event SwapInitiated(
        address indexed tokenIn,
        uint256 amountIn,
        address indexed target,
        address indexed spender,
        uint256 msgValue,
        bytes32 dataHash
    );
    event SwapAndReceiveInitiated(
        address indexed tokenIn,
        address indexed tokenOut,
        address indexed to,
        uint256 amountIn,
        address target,
        address spender,
        uint256 msgValue,
        bytes32 dataHash
    );
    event SwapAndReceiveCompleted(
        address indexed tokenOut,
        address indexed to,
        uint256 amountOut,
        bool depositedToProtocol
    );
    event WithdrawNativeProcessed(address indexed to, uint256 amount);

    error OnlyOwner();
    error OnlyOwnerOrFactory();
    error OnlyProcessor();
    error TokenNotActive();
    error FeeProcessingFailed();
    error TokenAlreadyInitialized();
    error SendingToOwner();
    error InsufficientFunds();
    error WithdrawingYieldToken();
    error WithdrawingProtocolToken();
    error TokenNotInitialized();
    error TokenAlreadyActive();
    error NetworkFeeExceedsMax();
    error NetworkFeeExceedsAmount();
    error UnauthorizedImplementation();
    error TargetHasNoCode();
    error DataTooShort();
    error TargetNotAllowed();
    error SpenderNotAllowed();
    error ProviderCallFailed();
    error TokenInResidue();
    error SwapPayoutNotReceived();
    error NativeTransferFailed();
    error TokenInEqualsTokenOut();
    error SendingToThis();

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

    function swap(
        address tokenIn,
        uint256 amountIn,
        address target,
        address spender,
        bytes calldata data
    )
        external
        payable;

    function swapAndReceive(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        address target,
        address spender,
        bytes calldata data
    )
        external
        payable;

    function protocolBalance(address yieldToken) external view returns (uint);
    
    function effectiveBalance(address yieldToken) external view returns (uint);

    function calculateServiceFee(address yieldToken) external view returns (uint);
}