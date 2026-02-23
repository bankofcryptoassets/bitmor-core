// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISwapAdaptor
 * @notice Interface for UniswapV4Swapper with simplified function signatures
 * @dev Pool config (fee, tickSpacing, hooks) stored as immutables in the contract
 */
interface ISwapAdaptor {
    /**
     * @notice Get maximum input tokens needed for exact output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountOut Exact amount of output tokens desired
     * @return maxAmountIn Maximum input tokens required (includes slippage buffer)
     */
    function getMaxTokenInAmount(address tokenIn, address tokenOut, uint256 exactAmountOut)
        external
        returns (uint256 maxAmountIn);

    /**
     * @notice Get minimum output tokens for exact input tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountIn Exact amount of input tokens to swap
     * @return minAmountOut Minimum output tokens expected (includes slippage buffer)
     */
    function getMinTokenOutAmount(address tokenIn, address tokenOut, uint256 exactAmountIn)
        external
        returns (uint256 minAmountOut);

    /**
     * @notice Swap exact input tokens for minimum output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountIn Exact amount of input tokens to swap
     * @param minAmountOut Minimum output tokens to receive (slippage protection)
     * @param recipient Address to receive the output tokens
     * @return amountOut Actual output tokens received
     */
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /**
     * @notice Swap maximum input tokens for exact output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountOut Exact amount of output tokens to receive
     * @param maxAmountIn Maximum input tokens willing to spend
     * @param recipient Address to receive the output tokens
     * @return amountIn Actual input tokens spent
     */
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) external returns (uint256 amountIn);
}
