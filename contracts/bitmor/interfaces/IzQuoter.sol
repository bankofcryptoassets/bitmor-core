// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title IzQuoter
 * @notice Interface for zQuoter - price quotation helper for zRouter
 * @dev Repository: https://github.com/zammdefi/zRouter
 * @dev Deployed on Base: 0x772E2810A471dB2CC7ADA0d37D6395476535889a
 */
interface IzQuoter {
  /**
   * @notice Get quote from V2-style pools
   * @dev Aerodrome is V2-compatible (fork of Velodrome/Solidly)
   * @param exactOut Whether to quote exact output (true) or exact input (false)
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param swapAmount Amount to swap (input amount for exactIn, output amount for exactOut)
   * @param sushi True for Sushiswap, false for Uniswap V2 style (use false for Aerodrome)
   * @return amountIn Input amount required (relevant for exactOut swaps)
   * @return amountOut Expected output amount (relevant for exactIn swaps)
   */
  function quoteV2(
    bool exactOut,
    address tokenIn,
    address tokenOut,
    uint256 swapAmount,
    bool sushi
  ) external returns (uint256 amountIn, uint256 amountOut);
}
