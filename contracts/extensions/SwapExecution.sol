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
        address spenderEffective;
        uint amountIn;
        uint feeIn;
        uint protocolBalBefore;
        uint pulledFromProtocol;
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
        if (_isEntryAllowed(tokenOut)) {
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

        context.spenderEffective = spenderEffective;
        context.tokenIn = IERC20(tokenIn);
        context.amountIn = amountIn;
        context.feeIn = calculateServiceFee(tokenIn);

        // use any stuck funds on the module
        uint moduleBal = context.tokenIn.balanceOf(address(this));
        uint needed = moduleBal >= amountIn ? 0 : amountIn - moduleBal;

        // take from owner if needed
        if (needed > 0) {
            uint ownerBal = context.tokenIn.balanceOf(owner);
            uint fromOwner = ownerBal >= needed ? needed : ownerBal;
            if (fromOwner > 0) {
                context.tokenIn.safeTransferFrom(owner, address(this), fromOwner);
            }
            needed -= fromOwner;
        }

        // pull from protocol directly to module if still needed
        if (needed > 0) {
            uint protocolBalBefore = _protocolBalance(tokenIn);
            require(protocolBalBefore >= needed + context.feeIn, InsufficientFunds());

            _pullFromProtocolToModule(tokenIn, needed);

            context.protocolBalBefore = protocolBalBefore;
            context.pulledFromProtocol = needed;
        }

        context.tokenIn.forceApprove(spenderEffective, amountIn);
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

        // process fee before handling residue to avoid inflating fee when the whole balance left is charged
        if (context.pulledFromProtocol > 0) {
            _processFeeAfterProtocolPull(
                address(context.tokenIn), context.feeIn, context.protocolBalBefore, context.pulledFromProtocol
            );
        }
    }
}
