// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISwapAdaptor} from "@bitmor/interfaces/ISwapAdaptor.sol";

/**
 * @title MockUniswapV4SwapAdapter
 * @author Bitmor Protocol
 * @notice Mock swap adapter for local testing
 * @dev Simulates swaps using a fixed exchange rate from oracle prices.
 *      This is for local testing only - not for production use.
 */
contract MockUniswapV4SwapAdapter is ISwapAdaptor {
    using SafeERC20 for IERC20;

    /// @notice Price oracle for getting asset prices
    address public immutable i_ORACLE;

    /// @notice BTC token address (8 decimals)
    address public immutable i_BTC;

    /// @notice USDC token address (6 decimals)
    address public immutable i_USDC;

    /// @notice BTC price in USD with 8 decimals (e.g., 100000e8 = $100,000)
    uint256 public btcPrice;

    /// @notice USDC price in USD with 8 decimals (e.g., 1e8 = $1)
    uint256 public usdcPrice;

    /**
     * @notice Emitted when a mock swap is executed
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens swapped
     * @param amountOut Amount of output tokens received
     * @param caller Address that initiated the swap
     */
    event MockSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed caller
    );

    /**
     * @notice Deploys the mock adapter with oracle and token addresses
     * @param _oracle The price oracle address
     * @param _btc The BTC token address
     * @param _usdc The USDC token address
     */
    constructor(address _oracle, address _btc, address _usdc) {
        i_ORACLE = _oracle;
        i_BTC = _btc;
        i_USDC = _usdc;
        // Default prices for testing
        btcPrice = 100_000e8; // $100,000
        usdcPrice = 1e8; // $1
    }

    /// @notice Set BTC price for testing
    function setBtcPrice(uint256 _price) external {
        btcPrice = _price;
    }

    /// @notice Set USDC price for testing
    function setUsdcPrice(uint256 _price) external {
        usdcPrice = _price;
    }

    /// @inheritdoc ISwapAdaptor
    function getMaxTokenInAmount(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut
    ) external view override returns (uint256 maxAmountIn) {
        maxAmountIn = _calculateInput(tokenIn, tokenOut, exactAmountOut);
    }

    /// @inheritdoc ISwapAdaptor
    function getMinTokenOutAmount(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn
    ) external view override returns (uint256 minAmountOut) {
        minAmountOut = _calculateOutput(tokenIn, tokenOut, exactAmountIn);
    }

    /// @inheritdoc ISwapAdaptor
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        address recipient
    ) external override returns (uint256 amountOut) {
        require(exactAmountIn > 0, "MockSwap: invalid amountIn");

        // Transfer tokens in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), exactAmountIn);

        // Calculate output based on prices
        amountOut = _calculateOutput(tokenIn, tokenOut, exactAmountIn);

        // Check slippage
        require(amountOut >= minAmountOut, "MockSwap: insufficient output");

        // Transfer tokens out to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit MockSwap(tokenIn, tokenOut, exactAmountIn, amountOut, msg.sender);
    }

    /// @inheritdoc ISwapAdaptor
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) external override returns (uint256 amountIn) {
        require(exactAmountOut > 0, "MockSwap: invalid amountOut");

        // Calculate required input
        amountIn = _calculateInput(tokenIn, tokenOut, exactAmountOut);

        // Check slippage
        require(amountIn <= maxAmountIn, "MockSwap: excessive input");

        // Transfer tokens in
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer exact tokens out to recipient
        IERC20(tokenOut).safeTransfer(recipient, exactAmountOut);

        emit MockSwap(tokenIn, tokenOut, amountIn, exactAmountOut, msg.sender);
    }

    /**
     * @notice Calculate output amount based on prices and decimals
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return amountOut Output amount
     */
    function _calculateOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        // Get prices
        uint256 priceIn = tokenIn == i_BTC ? btcPrice : usdcPrice;
        uint256 priceOut = tokenOut == i_BTC ? btcPrice : usdcPrice;

        // Get decimals
        uint8 decimalsIn = tokenIn == i_BTC ? 8 : 6;
        uint8 decimalsOut = tokenOut == i_BTC ? 8 : 6;

        // Calculate: amountOut = amountIn * priceIn / priceOut * (10^decimalsOut / 10^decimalsIn)
        // Using intermediate precision to avoid overflow/underflow
        uint256 valueInUsd = amountIn * priceIn; // amountIn * price (8 decimals)
        uint256 amountOut = valueInUsd / priceOut;

        // Adjust for decimal difference
        if (decimalsIn > decimalsOut) {
            amountOut = amountOut / (10 ** (decimalsIn - decimalsOut));
        } else if (decimalsOut > decimalsIn) {
            amountOut = amountOut * (10 ** (decimalsOut - decimalsIn));
        }

        return amountOut;
    }

    /**
     * @notice Calculate input amount needed for exact output
     * @dev Applies a 0.5% pool-rate discount to simulate AMM pricing dynamics.
     *      Real AMM pools quote slightly different from oracle mid-price due to
     *      pool state, fees, and price impact. This discount ensures the
     *      protocol's slippage buffer (applied externally in SwapLogic) doesn't
     *      push the required amount above available funds.
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountOut Desired output amount
     * @return amountIn Required input amount
     */
    function _calculateInput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (uint256) {
        // Get prices
        uint256 priceIn = tokenIn == i_BTC ? btcPrice : usdcPrice;
        uint256 priceOut = tokenOut == i_BTC ? btcPrice : usdcPrice;

        // Get decimals
        uint8 decimalsIn = tokenIn == i_BTC ? 8 : 6;
        uint8 decimalsOut = tokenOut == i_BTC ? 8 : 6;

        // Calculate: amountIn = amountOut * priceOut / priceIn * (10^decimalsIn / 10^decimalsOut)
        // Floor division (no round up) for conservative quoting
        uint256 valueInUsd = amountOut * priceOut;
        uint256 amountIn = valueInUsd / priceIn;

        // Adjust for decimal difference
        if (decimalsOut > decimalsIn) {
            amountIn = amountIn / (10 ** (decimalsOut - decimalsIn));
        } else if (decimalsIn > decimalsOut) {
            amountIn = amountIn * (10 ** (decimalsIn - decimalsOut));
        }

        // Apply 0.5% pool-rate discount (simulates favorable AMM execution vs oracle mid-price)
        amountIn = (amountIn * 9950) / 10000;

        return amountIn;
    }
}
