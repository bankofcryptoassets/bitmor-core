// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IzQuoter} from "../../interfaces/IzQuoter.sol";
import {ISwapAdaptor} from "../../interfaces/ISwapAdaptor.sol";
import {Errors} from "../helpers/Errors.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IERC20Metadata} from "../../dependencies/openzeppelin/IERC20Metadata.sol";

/**
 * @title SwapLogic
 * @author Bitmor Protocol
 * @notice Library for executing token swaps with optional zQuoter price validation
 * @dev Supports both Aerodrome (with zQuoter) and Uniswap V4 (without zQuoter).
 *
 * ## Swap Modes
 * - **Aerodrome (Base Mainnet)**: Uses zQuoter for price validation before swapping
 * - **Uniswap V4 (Base Sepolia)**: Uses oracle prices for minimum output calculation
 *
 * ## Slippage Protection
 * All swaps include slippage protection via `maxSlippageBps` parameter.
 * Minimum acceptable output is calculated as: `expectedOutput * (100% - slippage)`
 *
 * @custom:security Reverts if output amount is less than calculated minimum
 */
library SwapLogic {
    /**
     * @dev Basis points denominator for percentage calculations (100% = 10000)
     */
    uint256 constant BASIS_POINTS = 100_00;

    /**
     * @dev Flag for exact output swaps (false = exact input)
     */
    bool constant EXACT_OUT = false;

    /**
     * @dev Flag for Sushi router compatibility (false = Aerodrome V2-style)
     */
    bool constant SUSHI = false;

    /**
     * @dev Flag for stable pool swaps (false = volatile pools)
     */
    bool constant STABLE = false;

    /**
     * @dev Oracle price precision (8 decimals)
     */
    uint256 constant PRICE_PRECISION = 1e8;

    /**
     * @notice Execute swap via SwapAdaptor with optional zQuoter validation
     * @dev If zQuoter is address(0), skips price validation (testnet mode)
     * @param swapAdaptor SwapAdaptor contract address
     * @param tokenIn Input token (e.g., USDC)
     * @param tokenOut Output token (e.g., cbBTC)
     * @param amountIn Amount of input tokens
     * @param minAcceptable Minimum output amount
     * @return amountOut Actual output amount received
     */
    function executeSwap(
        address swapAdaptor,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAcceptable
    ) internal returns (uint256 amountOut) {
        // Execute swap via SwapAdaptor
        amountOut =
            ISwapAdaptor(swapAdaptor).swapExactTokensForTokens(tokenIn, tokenOut, amountIn, minAcceptable, STABLE);

        if (minAcceptable > amountOut) revert Errors.LessThanMinimumAmtReceived();

        return amountOut;
    }

    /**
     * @notice Calculates the minimum acceptable output amount for a swap with slippage protection
     * @dev Uses zQuoter for mainnet price discovery, or oracle prices for testnet fallback
     *
     * ## Calculation Methods
     * - **With zQuoter**: Queries expected output from Aerodrome quoter and applies slippage
     * - **Without zQuoter**: Uses oracle prices to calculate fair value and applies slippage
     *
     * @param zQuoter zQuoter contract address (address(0) for testnet/Uniswap V4 mode)
     * @param tokenIn Input token address (e.g., USDC)
     * @param tokenOut Output token address (e.g., cbBTC)
     * @param oracle Price oracle address for fallback calculation
     * @param amountIn Amount of input tokens to swap
     * @param maxSlippageBps Maximum acceptable slippage in basis points (e.g., 50 = 0.5%)
     * @return minAcceptable Minimum output amount after slippage tolerance
     */
    function calculateMinBTCAmt(
        address zQuoter,
        address tokenIn,
        address tokenOut,
        address oracle,
        uint256 amountIn,
        uint256 maxSlippageBps
    ) internal returns (uint256 minAcceptable) {
        //! TODO: Shift all swaps to Uniswap V4 router
        if (zQuoter != address(0)) {
            // Base Mainnet: Use zQuoter for Aerodrome price validation
            (, uint256 expectedOut) = IzQuoter(zQuoter)
                .quoteV2(
                    EXACT_OUT, // exactOut = false (we have exact input)
                    tokenIn, // USDC
                    tokenOut, // cbBTC
                    amountIn, // Amount to swap
                    SUSHI // sushi = false (Aerodrome is V2-style, not Sushi)
                );

            if (expectedOut == 0) revert Errors.ZeroAmount();

            // Calculate protocol's minimum acceptable output with slippage protection
            minAcceptable = (expectedOut * (BASIS_POINTS - maxSlippageBps)) / BASIS_POINTS;
        } else {
            uint256 tokenInPrice = IPriceOracleGetter(oracle).getAssetPrice(tokenIn);
            uint256 tokenOutPrice = IPriceOracleGetter(oracle).getAssetPrice(tokenOut);
            uint256 tokenInDecimals = 10 ** IERC20Metadata(tokenIn).decimals();
            uint256 tokenOutDecimals = 10 ** IERC20Metadata(tokenOut).decimals();

            uint256 tokenInUSDValue = (amountIn * tokenInPrice) / tokenInDecimals;
            uint256 tokenOutAmt = (tokenInUSDValue * tokenOutDecimals) / tokenOutPrice;

            minAcceptable = (tokenOutAmt * (BASIS_POINTS - maxSlippageBps)) / BASIS_POINTS;
        }
        return minAcceptable;
    }
}
