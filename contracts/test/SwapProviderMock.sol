// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapProviderMock {
    error MockRevert();

    function swapExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address sink
    ) 
        external 
        payable 
    {
        IERC20(tokenIn).transferFrom(msg.sender, sink, amountIn);

        if (tokenOut != address(0) && amountOut > 0) {
            IERC20(tokenOut).transfer(msg.sender, amountOut);
        }
    }

    function spendPartial(
        address tokenIn,
        uint256 amountIn,
        address sink
    ) 
        external 
    {
        require(amountIn > 0, "amountIn=0");
        IERC20(tokenIn).transferFrom(msg.sender, sink, amountIn - 1);
    }

    function swapNoPayout(
        address tokenIn,
        uint256 amountIn,
        address sink
    ) 
        external 
        payable 
    {
        IERC20(tokenIn).transferFrom(msg.sender, sink, amountIn);
    }

    function revertWithError() external pure {
        revert MockRevert();
    }

    function revertEmpty() external pure {
        revert();
    }
}