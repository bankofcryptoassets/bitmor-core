// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {IUniswapV4SwapAdapter} from '../interfaces/IUniswapV4SwapAdapter.sol';

/**
 * @title UniswapV4SwapAdapterWrapper
 * @notice Wrapper for UniswapV4SwapAdapterV2 to match ISwapAdaptor interface
 * @dev Adds compatibility layer: ISwapAdaptor (5 params) → IUniswapV4SwapAdapter (4 params)
 */
contract UniswapV4SwapAdapterWrapper {
  using SafeERC20 for IERC20;

  IUniswapV4SwapAdapter public immutable UNISWAP_ADAPTER;

  event Swapped(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );

  constructor(address _uniswapAdapter) public {
    require(_uniswapAdapter != address(0), 'Wrapper: invalid adapter');
    UNISWAP_ADAPTER = IUniswapV4SwapAdapter(_uniswapAdapter);
  }

  /**
   * @notice Swap exact input tokens for output tokens
   * @dev Matches ISwapAdaptor interface signature
   * @param tokenIn Input token address
   * @param tokenOut Output token address
   * @param amountIn Amount of input tokens to swap
   * @param minAmountOut Minimum output tokens to receive
   * @param stable Ignored - kept for ISwapAdaptor interface compatibility
   * @return amountOut Actual output tokens received
   */
  function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    bool stable
  ) external returns (uint256 amountOut) {
    require(amountIn > 0, 'Wrapper: invalid amountIn');

    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

    IERC20(tokenIn).safeApprove(address(UNISWAP_ADAPTER), amountIn);

    amountOut = UNISWAP_ADAPTER.swapExactTokensForTokens(tokenIn, tokenOut, amountIn, minAmountOut);

    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

    emit Swapped(tokenIn, tokenOut, amountIn, amountOut);

    return amountOut;
  }
}
