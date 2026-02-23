// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ISwapAdaptor} from "../../interfaces/ISwapAdaptor.sol";

import {Errors} from "../helpers/Errors.sol";

/**
 * @title SwapLogic
 * @author Bitmor Protocol
 * @notice Library for executing token swaps with slippage protection
 * @dev Wraps ISwapAdaptor calls with post-swap validation guards.
 *
 * ## Integration Context
 * - Used during loan initialization to swap USDC -> cbBTC (exact-out)
 * - Used during loan closure to swap cbBTC -> USDC (exact-in)
 * - Slippage bounds are computed from on-chain quotes + configurable BPS tolerance
 *
 * ## Invariant Context
 * - bvBTC shares MUST NOT be swappable or borrowable; swaps operate on the
 *   underlying cbBTC asset, not the vault shares (Invariant 1.6)
 */
library SwapLogic {
    using FixedPointMathLib for uint256;

    /// @dev Basis points denominator (10,000 = 100%) for slippage calculations
    uint256 constant BASIS_POINT_SCALE = 100_00;

    /**
     * @notice Executes an exact-output swap via the swap adapter
     * @dev Used during loan initialization to acquire exactly `exactAmountOut` of cbBTC.
     * MUST revert if `amountIn` exceeds `maxAmountIn` (slippage guard).
     * @param swapper Address of the ISwapAdaptor implementation
     * @param tokenIn Input token address (USDC)
     * @param tokenOut Output token address (cbBTC)
     * @param exactAmountOut Exact amount of `tokenOut` to receive
     * @param maxAmountIn Maximum amount of `tokenIn` to spend (slippage ceiling)
     * @param recipient Address to receive the output tokens
     * @return amountIn Actual amount of `tokenIn` consumed
     */
    function executeExactOutSwap(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) internal returns (uint256 amountIn) {
        amountIn = ISwapAdaptor(swapper).swapExactOutput(tokenIn, tokenOut, exactAmountOut, maxAmountIn, recipient);

        /// @dev Slippage guard: MUST revert if consumed input exceeds the maximum allowed
        if (amountIn > maxAmountIn) revert Errors.LessThanMinimumAmtReceived();

        return amountIn;
    }

    /**
     * @notice Executes an exact-input swap via the swap adapter
     * @dev Used during loan closure to convert cbBTC back to USDC.
     * MUST revert if `amountOut` falls below `minAmountAcceptable` (slippage guard).
     * @param swapper Address of the ISwapAdaptor implementation
     * @param tokenIn Input token address (cbBTC)
     * @param tokenOut Output token address (USDC)
     * @param exactAmountIn Exact amount of `tokenIn` to spend
     * @param minAmountAcceptable Minimum amount of `tokenOut` to receive (slippage floor)
     * @param recipient Address to receive the output tokens
     * @return amountOut Actual amount of `tokenOut` received
     */
    function executeExactInSwap(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountAcceptable,
        address recipient
    ) internal returns (uint256 amountOut) {
        amountOut =
            ISwapAdaptor(swapper).swapExactInput(tokenIn, tokenOut, exactAmountIn, minAmountAcceptable, recipient);

        /// @dev Slippage guard: MUST revert if received output is below the minimum acceptable
        if (minAmountAcceptable > amountOut) revert Errors.LessThanMinimumAmtReceived();

        return amountOut;
    }

    /**
     * @notice Calculates the maximum input amount with slippage tolerance for an exact-output swap
     * @dev Queries the swap adapter for an estimated input, then inflates by `slippageBps`.
     * Uses `mulDivUp` to round up, ensuring the ceiling is conservative.
     * @param swapper Address of the ISwapAdaptor implementation
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountOut Desired output amount
     * @param slippageBps Slippage tolerance in basis points
     * @return maxTokenIn Maximum input amount including slippage
     */
    function calculateMaxAmountIn(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 slippageBps
    ) internal returns (uint256 maxTokenIn) {
        uint256 amount = ISwapAdaptor(swapper).getMaxTokenInAmount(tokenIn, tokenOut, exactAmountOut);

        maxTokenIn = amount.mulDivUp(BASIS_POINT_SCALE + slippageBps, BASIS_POINT_SCALE);
    }

    /**
     * @notice Calculates the minimum output amount with slippage tolerance for an exact-input swap
     * @dev Queries the swap adapter for an estimated output, then deflates by `slippageBps`.
     * Uses `mulDivUp` to round up, making the floor less aggressive (slightly more permissive).
     * @param swapper Address of the ISwapAdaptor implementation
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param tokenInAmount Input amount
     * @param slippageBps Slippage tolerance in basis points
     * @return minTokenOut Minimum output amount after slippage
     */
    function calculateMinAmountOut(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        uint256 slippageBps
    ) internal returns (uint256 minTokenOut) {
        uint256 amount = ISwapAdaptor(swapper).getMinTokenOutAmount(tokenIn, tokenOut, tokenInAmount);

        minTokenOut = amount.mulDivUp(BASIS_POINT_SCALE - slippageBps, BASIS_POINT_SCALE);
    }
}
