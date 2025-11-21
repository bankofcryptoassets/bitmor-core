// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title IUniswapV4SwapAdapter
 * @notice Interface for UniswapV4SwapAdapterV2 contract
 * @dev Deployed at: 0x96C69Cd797a62C33FF805905dd241703A37F0020 (Base Sepolia)
 */
interface IUniswapV4SwapAdapter {
    /**
     * @notice Swap exact input tokens for output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum output (0 = auto-calculate with 5% slippage)
     * @return amountOut Actual output received
     */
    function swapExactTokensForTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    /**
     * @notice Swap with custom slippage tolerance
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @param slippageBps Slippage tolerance in basis points (100 = 1%)
     * @return amountOut Output amount
     */
    function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 slippageBps)
        external
        returns (uint256 amountOut);

    /**
     * @notice Estimate output amount for given input
     * @param tokenIn Input token address
     * @param amountIn Amount of input token
     * @return estimatedAmountOut Estimated output amount
     */
    function estimateOutput(address tokenIn, uint256 amountIn) external view returns (uint256 estimatedAmountOut);

    /**
     * @notice Check if pool is healthy for swaps
     * @return bool True if pool is initialized and has liquidity
     */
    function isPoolHealthy() external view returns (bool);

    /**
     * @notice Get current pool state
     * @return sqrtPriceX96 Current price
     * @return tick Current tick
     * @return liquidity Current liquidity
     * @return isHealthy Pool health status
     */
    function getPoolState() external view returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity, bool isHealthy);
}
