// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Requires } from "../common/Requires.sol";
import { YieldModuleLiquidUpgradeable } from "../core/YieldModuleLiquidUpgradeable.sol";
import { ISwapExecutionRegistry } from "../interfaces/ISwapExecutionRegistry.sol";

abstract contract SwapExecution is YieldModuleLiquidUpgradeable {
    using SafeERC20 for IERC20;
    using Requires for uint;
    using Requires for address;

    struct SwapContext {
        IERC20 tokenIn;
        address tokenInAddr;
        address spenderEffective;
        uint amountIn;
        uint feeIn;
        bool protocolTouched;
    }

    ISwapExecutionRegistry public immutable swapExecutionRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address swapExecutionRegistry_) {
        swapExecutionRegistry = ISwapExecutionRegistry(swapExecutionRegistry_);
    }

    function swap(
        address tokenIn,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    ) external payable onlyOwner nonReentrant {
        SwapContext memory context = _prepareSwap(tokenIn, amountIn, target, spender, data);

        _callProvider(target, data);

        _finalizeSwap(context);

        emit SwapInitiated(tokenIn, amountIn, target, context.spenderEffective, msg.value, keccak256(data));
    }

    function swapAndReceive(
        address tokenIn,
        address tokenOut,
        address to,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    ) external payable onlyOwner nonReentrant {
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

    function _prepareSwap(
        address tokenIn,
        uint amountIn,
        address target,
        address spender,
        bytes calldata data
    ) internal returns (SwapContext memory context) {
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
            if (protocolBal == needed + feeIn) {
                // avoid protocol rounding errors on withdrawing all available funds
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
        (bool success, bytes memory ret) = target.call{ value: msg.value }(data);
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
    }
}
