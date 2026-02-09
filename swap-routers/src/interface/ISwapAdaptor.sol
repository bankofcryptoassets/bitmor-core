// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ISwapAdaptor {
    function getMaxTokenInAmount(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint256 exactAmountOut
    ) external returns (uint256 maxAmountIn);

    function getMinTokenOutAmount(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint256 exactAmountIn
    ) external returns (uint256 minAmountOut);

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) external returns (uint256 amountIn);
}
