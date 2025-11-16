// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IzQuoter} from '../../interfaces/IzQuoter.sol';
import {ISwapAdaptor} from '../../interfaces/ISwapAdaptor.sol';

/**
 * @title SwapLogic
 * @notice Library for executing token swaps with optional zQuoter price validation
 * @dev Supports both Aerodrome (with zQuoter) and Uniswap V4 (without zQuoter)
 */
library SwapLogic {
  uint256 constant BASIS_POINTS = 100_00; // 100%

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
    amountOut = ISwapAdaptor(swapAdaptor).swapExactTokensForTokens(
      tokenIn,
      tokenOut,
      amountIn,
      minAcceptable,
      false
    );

    require(amountOut >= minAcceptable, 'SwapLogic: insufficient output amount');

    return amountOut;
  }

  function calculateMinBTCAmt(
    address zQuoter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 collateralAmount,
    uint256 maxSlippageBps
  ) internal returns (uint256 minAcceptable) {
    require(amountIn > 0, 'SwapLogic: invalid amountIn');

    if (zQuoter != address(0)) {
      // Base Mainnet: Use zQuoter for Aerodrome price validation
      (, uint256 expectedOut) = IzQuoter(zQuoter).quoteV2(
        false, // exactOut = false (we have exact input)
        tokenIn, // USDC
        tokenOut, // cbBTC
        amountIn, // Amount to swap
        false // sushi = false (Aerodrome is V2-style, not Sushi)
      );

      require(expectedOut > 0, 'SwapLogic: invalid quote from zQuoter');

      // Calculate protocol's minimum acceptable output with slippage protection
      minAcceptable = (expectedOut * (BASIS_POINTS - maxSlippageBps)) / BASIS_POINTS;
    } else {
      // minAcceptable = minAmountOut * (100% - slippage%) = minAmountOut * (10000 - 200) / 10000
      minAcceptable = (collateralAmount * (BASIS_POINTS - maxSlippageBps)) / BASIS_POINTS;
    }
    return minAcceptable;
  }
}
