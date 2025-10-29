// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title IzRouter
 * @notice Interface for zRouter on Base network (Aerodrome DEX)
 * @dev Based on: https://github.com/zammdefi/zRouter/blob/main/src/IzRouter.sol
 */
interface IzRouter {
  // ══════════════════════════════════════════════════════════════════════════════
  // AERODROME FUNCTIONS (Base Chain Only)
  // ══════════════════════════════════════════════════════════════════════════════

  /// @notice Swap tokens on Aerodrome (V2-style pools)
  /// @param to Recipient address
  /// @param stable Whether to use stable pool (true) or volatile pool (false)
  /// @param tokenIn Input token address (use address(0) for ETH)
  /// @param tokenOut Output token address (use address(0) for ETH)
  /// @param swapAmount Amount of input tokens to swap
  /// @param amountLimit Minimum output amount (slippage protection)
  /// @param deadline Transaction deadline
  /// @return amountIn Amount of input tokens used
  /// @return amountOut Amount of output tokens received
  function swapAero(
    address to,
    bool stable,
    address tokenIn,
    address tokenOut,
    uint256 swapAmount,
    uint256 amountLimit,
    uint256 deadline
  ) external payable returns (uint256 amountIn, uint256 amountOut);

  /// @notice Swap tokens on Aerodrome CL (Concentrated Liquidity pools)
  /// @param to Recipient address
  /// @param exactOut Whether this is an exact output swap
  /// @param tickSpacing Tick spacing for the pool
  /// @param tokenIn Input token address (use address(0) for ETH)
  /// @param tokenOut Output token address (use address(0) for ETH)
  /// @param swapAmount Amount to swap (input amount for exactIn, output amount for exactOut)
  /// @param amountLimit Slippage limit (max input for exactOut, min output for exactIn)
  /// @param deadline Transaction deadline
  /// @return amountIn Amount of input tokens used
  /// @return amountOut Amount of output tokens received
  function swapAeroCL(
    address to,
    bool exactOut,
    int24 tickSpacing,
    address tokenIn,
    address tokenOut,
    uint256 swapAmount,
    uint256 amountLimit,
    uint256 deadline
  ) external payable returns (uint256 amountIn, uint256 amountOut);
}
