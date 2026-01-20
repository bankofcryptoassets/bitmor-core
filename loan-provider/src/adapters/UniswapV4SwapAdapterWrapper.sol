// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV4SwapAdapter} from "../interfaces/IUniswapV4SwapAdapter.sol";

/**
 * @title UniswapV4SwapAdapterWrapper
 * @author Bitmor Protocol
 * @notice Wrapper for UniswapV4SwapAdapterV2 to match ISwapAdaptor interface
 * @dev Provides a compatibility layer between the protocol's 5-parameter swap interface
 * and Uniswap V4's 4-parameter interface.
 *
 * ## Purpose
 * The Bitmor Protocol uses `ISwapAdaptor` with a `stable` parameter for Aerodrome
 * compatibility. This wrapper ignores the `stable` parameter and forwards calls
 * to the Uniswap V4 adapter.
 *
 * ## Flow
 * 1. Receive tokens from caller
 * 2. Approve Uniswap V4 adapter
 * 3. Execute swap via Uniswap V4
 * 4. Transfer output tokens back to caller
 *
 * @custom:security Uses SafeERC20 for safe token transfers
 */
contract UniswapV4SwapAdapterWrapper {
    using SafeERC20 for IERC20;

    /**
     * @notice The underlying Uniswap V4 swap adapter contract
     */
    IUniswapV4SwapAdapter public immutable i_UNISWAP_ADAPTER;

    /**
     * @notice Emitted when a swap is executed through this wrapper
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens swapped
     * @param amountOut Amount of output tokens received
     */
    event UniswapV4SwapAdapterWrapper__Swapped(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /**
     * @notice Initializes the wrapper with the Uniswap V4 adapter address
     * @param _uniswapAdapter Address of the IUniswapV4SwapAdapter implementation
     */
    constructor(address _uniswapAdapter) {
        require(_uniswapAdapter != address(0), "Wrapper: invalid adapter");
        i_UNISWAP_ADAPTER = IUniswapV4SwapAdapter(_uniswapAdapter);
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
        require(amountIn > 0, "Wrapper: invalid amountIn");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        IERC20(tokenIn).forceApprove(address(i_UNISWAP_ADAPTER), amountIn);

        amountOut = i_UNISWAP_ADAPTER.swapExactTokensForTokens(tokenIn, tokenOut, amountIn, minAmountOut);

        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit UniswapV4SwapAdapterWrapper__Swapped(tokenIn, tokenOut, amountIn, amountOut);

        return amountOut;
    }
}
