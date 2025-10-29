// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IzQuoter} from '../../interfaces/IzQuoter.sol';
import {ISwapAdaptor} from '../../interfaces/ISwapAdaptor.sol';

/**
 * @title SwapLogic
 * @notice Library for executing token swaps with zQuoter price validation
 * @dev Uses zQuoter to get Aerodrome DEX quotes before executing swaps
 */
library SwapLogic {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  uint256 private constant BASIS_POINTS = 10000;

  /**
   * @notice Execute swap via SwapAdaptor with zQuoter
   * @dev Gets Aerodrome quote from zQuoter, then executes swap
   * @param swapAdaptor SwapAdaptor contract address
   * @param zQuoter zQuoter contract address for Aerodrome quotes
   * @param tokenIn Input token (e.g., USDC)
   * @param tokenOut Output token (e.g., cbBTC)
   * @param amountIn Amount of input tokens
   * @param minAmountOut Minimum output amount
   * @param maxSlippageBps Max slippage in basis points (5 = 0.05%)
   * @return amountOut Actual output amount received
   */
  function executeSwap(
    address swapAdaptor,
    address zQuoter,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    uint256 maxSlippageBps
  ) internal returns (uint256 amountOut) {
    require(amountIn > 0, 'SwapLogic: invalid amountIn');
    require(minAmountOut > 0, 'SwapLogic: invalid minAmountOut');
    require(maxSlippageBps <= BASIS_POINTS, 'SwapLogic: invalid slippage');

    // Get Aerodrome quote from zQuoter
    (, uint256 expectedOut) = IzQuoter(zQuoter).quoteV2(
      false, // exactOut = false (we have exact input)
      tokenIn, // USDC
      tokenOut, // cbBTC
      amountIn, // Amount to swap
      false // sushi = false (Aerodrome is V2-style, not Sushi)
    );

    require(expectedOut > 0, 'SwapLogic: invalid quote from zQuoter');

    // Calculate protocol's minimum acceptable output with slippage protection
    uint256 minAcceptable = expectedOut.mul(BASIS_POINTS.sub(maxSlippageBps)).div(BASIS_POINTS);

    // Validate user's expectation is reasonable (not exceeding the quote)
    require(minAmountOut <= expectedOut, 'SwapLogic: minAmountOut exceeds zQuoter quote');

    // Approve SwapAdaptor to spend tokens
    IERC20(tokenIn).safeApprove(swapAdaptor, amountIn);

    // Get balance before swap
    uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

    // Execute swap via SwapAdaptor (which calls zRouter.swapAero for Aerodrome)
    // Use protocol's calculated minimum (minAcceptable), not user's minAmountOut
    // USDC/cbBTC is a volatile pair, so stable = false
    amountOut = ISwapAdaptor(swapAdaptor).swapExactTokensForTokens(
      tokenIn,
      tokenOut,
      amountIn,
      minAcceptable, // Use protocol's calculated minimum with slippage protection
      false // stable = false for USDC/cbBTC volatile pair
    );

    // Verify balance increased by expected amount
    uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
    uint256 actualReceived = balanceAfter.sub(balanceBefore);

    require(actualReceived >= amountOut, 'SwapLogic: balance mismatch');
    require(amountOut >= minAcceptable, 'SwapLogic: insufficient output amount');

    return amountOut;
  }
}
