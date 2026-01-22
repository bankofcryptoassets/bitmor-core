// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV4SwapAdapter} from "../interfaces/IUniswapV4SwapAdapter.sol";

/**
 * @title MockUniswapV4SwapAdapter
 * @author Bitmor Protocol
 * @notice Mock swap adapter for local testing
 * @dev Simulates swaps using a fixed exchange rate from oracle prices.
 *      This is for local testing only - not for production use.
 */
contract MockUniswapV4SwapAdapter is IUniswapV4SwapAdapter {
    using SafeERC20 for IERC20;

    /// @notice Price oracle for getting asset prices
    address public immutable i_ORACLE;

    /// @notice BTC token address (8 decimals)
    address public immutable i_BTC;

    /// @notice USDC token address (6 decimals)
    address public immutable i_USDC;

    /// @notice BTC price in USD with 8 decimals (e.g., 100000e8 = $100,000)
    uint256 public btcPrice;

    /// @notice USDC price in USD with 8 decimals (e.g., 1e8 = $1)
    uint256 public usdcPrice;

    event MockSwap(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address indexed caller
    );

    constructor(address _oracle, address _btc, address _usdc) {
        i_ORACLE = _oracle;
        i_BTC = _btc;
        i_USDC = _usdc;
        // Default prices for testing
        btcPrice = 100_000e8; // $100,000
        usdcPrice = 1e8; // $1
    }

    /// @notice Set BTC price for testing
    function setBtcPrice(uint256 _price) external {
        btcPrice = _price;
    }

    /// @notice Set USDC price for testing
    function setUsdcPrice(uint256 _price) external {
        usdcPrice = _price;
    }

    /**
     * @inheritdoc IUniswapV4SwapAdapter
     */
    function swapExactTokensForTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        override
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "MockSwap: invalid amountIn");

        // Transfer tokens in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output based on prices
        amountOut = _calculateOutput(tokenIn, tokenOut, amountIn);

        // Check slippage
        require(amountOut >= minAmountOut, "MockSwap: insufficient output");

        // Transfer tokens out
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit MockSwap(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    /**
     * @inheritdoc IUniswapV4SwapAdapter
     */
    function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 slippageBps)
        external
        override
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "MockSwap: invalid amountIn");

        // Transfer tokens in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output based on prices
        amountOut = _calculateOutput(tokenIn, tokenOut, amountIn);

        // Apply slippage
        uint256 minAmountOut = amountOut * (10000 - slippageBps) / 10000;

        // Transfer tokens out
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit MockSwap(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
    }

    /**
     * @inheritdoc IUniswapV4SwapAdapter
     */
    function estimateOutput(address tokenIn, uint256 amountIn)
        external
        view
        override
        returns (uint256 estimatedAmountOut)
    {
        address tokenOut = tokenIn == i_BTC ? i_USDC : i_BTC;
        return _calculateOutput(tokenIn, tokenOut, amountIn);
    }

    /**
     * @inheritdoc IUniswapV4SwapAdapter
     */
    function isPoolHealthy() external pure override returns (bool) {
        return true;
    }

    /**
     * @inheritdoc IUniswapV4SwapAdapter
     */
    function getPoolState()
        external
        pure
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity, bool isHealthy)
    {
        // Return mock values
        return (0, 0, type(uint128).max, true);
    }

    /**
     * @notice Calculate output amount based on prices and decimals
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return amountOut Output amount
     */
    function _calculateOutput(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        // Get prices
        uint256 priceIn = tokenIn == i_BTC ? btcPrice : usdcPrice;
        uint256 priceOut = tokenOut == i_BTC ? btcPrice : usdcPrice;

        // Get decimals
        uint8 decimalsIn = tokenIn == i_BTC ? 8 : 6;
        uint8 decimalsOut = tokenOut == i_BTC ? 8 : 6;

        // Calculate: amountOut = amountIn * priceIn / priceOut * (10^decimalsOut / 10^decimalsIn)
        // Using intermediate precision to avoid overflow/underflow
        uint256 valueInUsd = amountIn * priceIn; // amountIn * price (8 decimals)
        uint256 amountOut = valueInUsd / priceOut;

        // Adjust for decimal difference
        if (decimalsIn > decimalsOut) {
            amountOut = amountOut / (10 ** (decimalsIn - decimalsOut));
        } else if (decimalsOut > decimalsIn) {
            amountOut = amountOut * (10 ** (decimalsOut - decimalsIn));
        }

        return amountOut;
    }
}
