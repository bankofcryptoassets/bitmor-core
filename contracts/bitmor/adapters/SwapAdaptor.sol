// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IzRouter} from '../interfaces/IzRouter.sol';

/**
 * @title SwapAdaptor
 * @notice Adapter for Aerodrome DEX swaps via zRouter on Base network
 */
contract SwapAdaptor {
  using SafeERC20 for IERC20;

  IzRouter public immutable i_ZROUTER; //0x0000000000404FECAf36E6184245475eE1254835 on Base

  event SwapAdaptor__Swapped(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );

  constructor(address _zRouter) public {
    require(_zRouter != address(0), 'SwapAdaptor: invalid zRouter');
    i_ZROUTER = IzRouter(_zRouter);
  }

  /**
   * @notice Swap exact input tokens for output tokens via Aerodrome pool
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param amountIn Amount of input tokens to swap
   * @param minAmountOut Minimum output tokens (slippage protection)
   * @param stable True for stable pools, false for volatile pools
   * @return amountOut Actual output tokens received
   */
  function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    bool stable
  ) external returns (uint256 amountOut) {
    require(amountIn > 0, 'SwapAdaptor: invalid amountIn');

    // Pull tokens from caller
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

    // Approve zRouter
    IERC20(tokenIn).forceApprove(address(i_ZROUTER), 0);
    IERC20(tokenIn).forceApprove(address(i_ZROUTER), amountIn);

    (, amountOut) = i_ZROUTER.swapAero(
      msg.sender, // recipient
      stable,
      tokenIn,
      tokenOut,
      amountIn,
      minAmountOut,
      block.timestamp
    );

    require(amountOut >= minAmountOut, 'SwapAdaptor: insufficient output');

    emit SwapAdaptor__Swapped(tokenIn, tokenOut, amountIn, amountOut);

    return amountOut;
  }

  /**
   * @notice Swap via Aerodrome concentrated liquidity pool
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param amountIn Amount of input tokens to swap
   * @param minAmountOut Minimum output tokens
   * @param tickSpacing Tick spacing for the pool
   * @return amountOut Actual output tokens received
   */
  function swapExactTokensForTokensCL(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    int24 tickSpacing
  ) external returns (uint256 amountOut) {
    require(amountIn > 0, 'SwapAdaptor: invalid amountIn');

    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

    IERC20(tokenIn).forceApprove(address(i_ZROUTER), 0);
    IERC20(tokenIn).forceApprove(address(i_ZROUTER), amountIn);

    (, amountOut) = i_ZROUTER.swapAeroCL(
      msg.sender, // recipient
      false, // exactOut = false (we're doing exact input)
      tickSpacing,
      tokenIn,
      tokenOut,
      amountIn,
      minAmountOut,
      block.timestamp
    );

    require(amountOut >= minAmountOut, 'SwapAdaptor: insufficient output');

    emit SwapAdaptor__Swapped(tokenIn, tokenOut, amountIn, amountOut);

    return amountOut;
  }
}
