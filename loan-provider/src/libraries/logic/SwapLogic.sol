// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IzQuoter} from "../../interfaces/IzQuoter.sol";
import {ISwapAdaptor} from "../../interfaces/ISwapAdaptor.sol";
import {Errors} from "../helpers/Errors.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IERC20Metadata} from "../../dependencies/openzeppelin/IERC20Metadata.sol";

/**
 * @title SwapLogic
 * @notice Library for executing token swaps with optional zQuoter price validation
 * @dev Supports both Aerodrome (with zQuoter) and Uniswap V4 (without zQuoter)
 */
library SwapLogic {
    uint256 constant BASIS_POINTS = 100_00; // 100%
    bool constant EXACT_OUT = false;
    bool constant SUSHI = false;
    bool constant STABLE = false;
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

    function calculateMinBTCAmt(
        address zQuoter,
        address tokenIn,
        address tokenOut,
        address oracle,
        uint256 amountIn,
        uint256 maxSlippageBps
    ) internal returns (uint256 minAcceptable) {
        //! TODO: Shift all to Uniswap
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
