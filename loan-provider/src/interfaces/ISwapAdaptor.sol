// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title ISwapAdapter
 * @notice Interface for SwapAdapter contract
 */
interface ISwapAdaptor {
    /**
     * @notice Swap exact input tokens for output tokens via Aerodrome standard pool
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens to swap
     * @param minAmountOut Minimum output tokens to receive
     * @param stable True for stable pools, false for volatile pools
     * @return amountOut Actual output tokens received
     */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bool stable
    ) external returns (uint256 amountOut);

    /**
     * @notice Swap via Aerodrome concentrated liquidity pool
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens to swap
     * @param minAmountOut Minimum output tokens to receive
     * @param tickSpacing Tick spacing for CL pool (50, 100, 200)
     * @return amountOut Actual output tokens received
     */
    function swapExactTokensForTokensCL(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        int24 tickSpacing
    ) external returns (uint256 amountOut);
}
