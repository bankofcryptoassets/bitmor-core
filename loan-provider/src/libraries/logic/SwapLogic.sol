// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ISwapAdaptor} from "../../interfaces/ISwapAdaptor.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";

import {Errors} from "../helpers/Errors.sol";

library SwapLogic {
    using FixedPointMathLib for uint256;

    uint256 constant BASIS_POINT_SCALE = 100_00;

    function executeExactOutSwap(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) internal returns (uint256 amountIn) {
        amountIn = ISwapAdaptor(swapper).swapExactOutput(
            tokenIn,
            tokenOut,
            exactAmountOut,
            maxAmountIn,
            recipient
        );

        if (amountIn > maxAmountIn) revert Errors.LessThanMinimumAmtReceived();

        return amountIn;
    }

    function executeExactInSwap(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountAcceptable,
        address recipient
    ) internal returns (uint256 amountOut) {
        amountOut = ISwapAdaptor(swapper).swapExactInput(
            tokenIn,
            tokenOut,
            exactAmountIn,
            minAmountAcceptable,
            recipient
        );

        if (minAmountAcceptable > amountOut) revert Errors.LessThanMinimumAmtReceived();

        return amountOut;
    }

    function calculateMaxAmountIn(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 slippageBps
    ) internal returns (uint256 maxTokenIn) {
        uint256 amount = ISwapAdaptor(swapper).getMaxTokenInAmount(
            tokenIn,
            tokenOut,
            exactAmountOut
        );

        maxTokenIn = amount.mulDivUp(BASIS_POINT_SCALE + slippageBps, BASIS_POINT_SCALE);
    }

    function calculateMinAmountOut(
        address swapper,
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        uint256 slippageBps
    ) internal returns (uint256 minTokenOut) {
        uint256 amount = ISwapAdaptor(swapper).getMinTokenOutAmount(
            tokenIn,
            tokenOut,
            tokenInAmount
        );

        minTokenOut = amount.mulDivUp(BASIS_POINT_SCALE - slippageBps, BASIS_POINT_SCALE);
    }
}
