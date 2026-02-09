// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapAdaptor} from "../interface/ISwapAdaptor.sol";

/**
 * @title UniswapV4Swapper
 * @notice Swap adapter for Uniswap V4 with pool config stored as immutables
 * @dev Pool configuration (fee, tickSpacing, hooks) is set at deployment
 */
contract UniswapV4Swapper is ISwapAdaptor {
    using SafeERC20 for IERC20;

    IUniversalRouter public immutable i_UNIVERSAL_ROUTER;
    IV4Quoter public immutable i_QUOTER;

    // Pool configuration (set once at deployment)
    uint24 public immutable i_FEE;
    int24 public immutable i_TICK_SPACING;
    address public immutable i_HOOKS;

    constructor(
        address _universalRouter,
        address _quoter,
        uint24 _fee,
        int24 _tickSpacing,
        address _hooks
    ) {
        i_UNIVERSAL_ROUTER = IUniversalRouter(_universalRouter);
        i_QUOTER = IV4Quoter(_quoter);
        i_FEE = _fee;
        i_TICK_SPACING = _tickSpacing;
        i_HOOKS = _hooks;
    }

    /**
     * @notice Helper function to build PoolKey using stored immutables
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return poolKey The constructed PoolKey struct
     * @return zeroForOne True if tokenIn is currency0, false otherwise
     */
    function _buildPoolKey(
        address tokenIn,
        address tokenOut
    ) internal view returns (PoolKey memory poolKey, bool zeroForOne) {
        // Uniswap V4 requires currency0 < currency1 (sorted by address)
        if (tokenIn < tokenOut) {
            poolKey = PoolKey({
                currency0: Currency.wrap(tokenIn),
                currency1: Currency.wrap(tokenOut),
                fee: i_FEE,
                tickSpacing: i_TICK_SPACING,
                hooks: IHooks(i_HOOKS)
            });
            zeroForOne = true; // tokenIn is currency0, so we swap 0 -> 1
        } else {
            poolKey = PoolKey({
                currency0: Currency.wrap(tokenOut),
                currency1: Currency.wrap(tokenIn),
                fee: i_FEE,
                tickSpacing: i_TICK_SPACING,
                hooks: IHooks(i_HOOKS)
            });
            zeroForOne = false; // tokenIn is currency1, so we swap 1 -> 0
        }
    }

    /**
     * @notice Get maximum input tokens needed for exact output tokens
     * @dev Uses Uniswap V4 Quoter to simulate the swap and get accurate quote
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountOut Exact amount of output tokens desired
     * @return maxAmountIn Maximum input tokens required (with 0.5% slippage buffer)
     */
    function getMaxTokenInAmount(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut
    ) external returns (uint256 maxAmountIn) {
        (PoolKey memory poolKey, bool zeroForOne) = _buildPoolKey(tokenIn, tokenOut);

        // Use Quoter to simulate exact output swap
        (uint256 quotedInput,) = i_QUOTER.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                exactAmount: uint128(exactAmountOut),
                hookData: bytes("")
            })
        );

        // Add 0.5% slippage buffer
        return (quotedInput * 10050) / 10000;
    }

    /**
     * @notice Get minimum output tokens for exact input tokens
     * @dev Uses Uniswap V4 Quoter to simulate the swap and get accurate quote
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountIn Exact amount of input tokens to swap
     * @return minAmountOut Minimum output tokens expected (with 0.5% slippage buffer)
     */
    function getMinTokenOutAmount(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn
    ) external returns (uint256 minAmountOut) {
        (PoolKey memory poolKey, bool zeroForOne) = _buildPoolKey(tokenIn, tokenOut);

        // Use Quoter to simulate exact input swap
        (uint256 quotedOutput,) = i_QUOTER.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                exactAmount: uint128(exactAmountIn),
                hookData: bytes("")
            })
        );

        // Subtract 0.5% slippage buffer (get minimum acceptable)
        return (quotedOutput * 9950) / 10000;
    }

    /**
     * @notice Swap exact input tokens for minimum output tokens
     * @dev Uses UniversalRouter for the actual swap execution
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountIn Exact amount of input tokens to swap
     * @param minAmountOut Minimum output tokens to receive (slippage protection)
     * @param recipient Address to receive the output tokens
     * @return amountOut Actual output tokens received
     */
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        require(exactAmountIn > 0, "Invalid input amount");
        require(minAmountOut > 0, "Invalid min output");
        require(recipient != address(0), "Invalid recipient");

        // Pull exact input tokens from caller and send to UniversalRouter
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(i_UNIVERSAL_ROUTER), exactAmountIn);

        // Execute the swap with exact input
        _executeSwapExactIn(tokenIn, tokenOut, exactAmountIn, minAmountOut);

        // Get actual output amount received
        amountOut = IERC20(tokenOut).balanceOf(address(this));
        require(amountOut >= minAmountOut, "Insufficient output amount");

        // Transfer all output tokens to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        return amountOut;
    }

    /**
     * @notice Swap exact output tokens for maximum input tokens
     * @dev Uses UniversalRouter for the actual swap execution
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param exactAmountOut Exact amount of output tokens to receive
     * @param maxAmountIn Maximum input tokens willing to spend
     * @param recipient Address to receive the output tokens
     * @return amountIn Actual input tokens spent
     */
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) external returns (uint256 amountIn) {
        require(exactAmountOut > 0, "Invalid output amount");
        require(maxAmountIn > 0, "Invalid max input");
        require(recipient != address(0), "Invalid recipient");

        // Pull input tokens from caller and send to UniversalRouter
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(i_UNIVERSAL_ROUTER), maxAmountIn);

        // Execute the swap
        _executeSwapExactOut(tokenIn, tokenOut, exactAmountOut, maxAmountIn);

        // Calculate actual amount used and refund excess
        amountIn = _handleRefund(tokenIn, maxAmountIn);

        // Transfer exact output tokens to recipient
        IERC20(tokenOut).safeTransfer(recipient, exactAmountOut);

        return amountIn;
    }

    /**
     * @notice Internal function to execute exact input swap via UniversalRouter
     * @dev Uses V4_SWAP command with Actions encoding
     */
    function _executeSwapExactIn(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) internal {
        (PoolKey memory poolKey, bool zeroForOne) = _buildPoolKey(tokenIn, tokenOut);

        // Build the actions sequence: SWAP -> SETTLE -> TAKE
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE), uint8(Actions.TAKE_ALL));

        // Build params for each action
        bytes[] memory params = new bytes[](3);

        // Param 0: ExactInputSingleParams for the swap
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(exactAmountIn),
                amountOutMinimum: uint128(minAmountOut),
                hookData: bytes("")
            })
        );

        // Param 1: SETTLE - (currency, amount, payerIsUser)
        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        params[1] = abi.encode(inputCurrency, exactAmountIn, false);

        // Param 2: TAKE_ALL - (currency, minAmount)
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
        params[2] = abi.encode(outputCurrency, minAmountOut);

        // Encode the V4_SWAP input: (actions, params)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute via UniversalRouter with 1 hour deadline
        i_UNIVERSAL_ROUTER.execute(abi.encodePacked(uint8(Commands.V4_SWAP)), inputs, block.timestamp + 3600);
    }

    /**
     * @notice Internal function to execute exact output swap via UniversalRouter
     * @dev Uses V4_SWAP command followed by SWEEP command
     */
    function _executeSwapExactOut(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn
    ) internal {
        (PoolKey memory poolKey, bool zeroForOne) = _buildPoolKey(tokenIn, tokenOut);

        Currency inputCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        // Build V4 actions: SWAP -> SETTLE -> TAKE
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE), uint8(Actions.TAKE_ALL));

        // Build params for each V4 action
        bytes[] memory v4Params = new bytes[](3);

        // Param 0: ExactOutputSingleParams for the swap
        v4Params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountOut: uint128(exactAmountOut),
                amountInMaximum: uint128(maxAmountIn),
                hookData: bytes("")
            })
        );

        // Param 1: SETTLE - (currency, amount, payerIsUser)
        v4Params[1] = abi.encode(inputCurrency, uint256(0), false); // 0 = OPEN_DELTA

        // Param 2: TAKE_ALL - (currency, minAmount)
        v4Params[2] = abi.encode(outputCurrency, 0);

        // Build Universal Router commands: V4_SWAP + SWEEP
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.SWEEP));

        // Build inputs for each command
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(actions, v4Params); // V4_SWAP input
        inputs[1] = abi.encode(tokenIn, address(this), 0); // SWEEP: (token, recipient, minAmount)

        // Execute via UniversalRouter with 1 hour deadline
        i_UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp + 3600);
    }

    /**
     * @notice Internal function to handle refund of unused input tokens
     * @return amountIn Actual amount of input tokens used
     */
    function _handleRefund(address tokenIn, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        uint256 remainingBalance = IERC20(tokenIn).balanceOf(address(this));
        amountIn = maxAmountIn - remainingBalance;

        // Refund unused input tokens to caller
        if (remainingBalance > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, remainingBalance);
        }
    }
}
