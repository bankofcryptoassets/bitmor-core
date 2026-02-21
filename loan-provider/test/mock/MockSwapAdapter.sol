// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ISwapAdaptor} from "@bitmor/interfaces/ISwapAdaptor.sol";
import {MockPriceOracle} from "./MockPriceOracle.sol";

/// @title MockSwapAdapter
/// @author Bitmor Protocol
/// @notice Mock swap adapter for unit testing
/// @dev Swaps tokens using oracle prices with configurable slippage
contract MockSwapAdapter is ISwapAdaptor {
    /// @notice The price oracle for determining swap rates
    MockPriceOracle public oracle;

    /// @notice Slippage in basis points (e.g., 50 = 0.5%)
    uint256 public slippageBps;

    /// @notice Whether swaps should revert
    bool public shouldRevert;

    /// @notice When set, swapExactInput returns this value instead of calculating from oracle
    uint256 public fixedOutput;

    /// @notice Whether to use fixed output mode
    bool public useFixedOutput;

    /// @notice Emitted when a swap is executed
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @notice Creates a new MockSwapAdapter
    /// @param _oracle The price oracle address
    constructor(address _oracle) {
        oracle = MockPriceOracle(_oracle);
    }

    /// @notice Set the slippage for swaps
    /// @param _slippageBps Slippage in basis points
    function setSlippage(uint256 _slippageBps) external {
        slippageBps = _slippageBps;
    }

    /// @notice Set whether swaps should revert
    /// @param _shouldRevert True to make swaps revert
    function setSwapReverts(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @notice Set a fixed output amount for swapExactInput (bypasses oracle calculation)
    /// @param _output The exact amount to return from swapExactInput
    function setFixedOutput(uint256 _output) external {
        fixedOutput = _output;
        useFixedOutput = true;
    }

    /// @notice Clear fixed output mode, returning to oracle-based pricing
    function clearFixedOutput() external {
        useFixedOutput = false;
        fixedOutput = 0;
    }

    /// @inheritdoc ISwapAdaptor
    function getMaxTokenInAmount(address tokenIn, address tokenOut, uint256 exactAmountOut)
        external
        view
        override
        returns (uint256 maxAmountIn)
    {
        maxAmountIn = _calculateInput(tokenIn, tokenOut, exactAmountOut);
    }

    /// @inheritdoc ISwapAdaptor
    function getMinTokenOutAmount(address tokenIn, address tokenOut, uint256 exactAmountIn)
        external
        view
        override
        returns (uint256 minAmountOut)
    {
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
        require(!shouldRevert, "Swap reverted");

        if (useFixedOutput) {
            amountOut = fixedOutput;
        } else {
            amountOut = _calculateOutput(tokenIn, tokenOut, exactAmountIn);

            // Apply slippage
            if (slippageBps > 0) {
                amountOut = (amountOut * (10000 - slippageBps)) / 10000;
            }
        }

        // Skip minAmountOut check in fixed output mode (we're testing protocol-level guards)
        if (!useFixedOutput) {
            require(amountOut >= minAmountOut, "Slippage exceeded");
        }

        // Execute transfer
        IERC20(tokenIn).transferFrom(msg.sender, address(this), exactAmountIn);
        IERC20(tokenOut).transfer(recipient, amountOut);

        emit Swap(tokenIn, tokenOut, exactAmountIn, amountOut);
    }

    /// @inheritdoc ISwapAdaptor
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        address recipient
    ) external override returns (uint256 amountIn) {
        require(!shouldRevert, "Swap reverted");

        amountIn = _calculateInput(tokenIn, tokenOut, exactAmountOut);

        // Apply slippage (input increases)
        if (slippageBps > 0) {
            amountIn = (amountIn * (10000 + slippageBps)) / 10000;
        }

        require(amountIn <= maxAmountIn, "Slippage exceeded");

        // Execute transfer
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(recipient, exactAmountOut);

        emit Swap(tokenIn, tokenOut, amountIn, exactAmountOut);
    }

    /// @notice Fund the adapter with tokens for swaps
    /// @param token The token to fund
    /// @param amount The amount to fund
    function fund(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Calculate output amount given input
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @return amountOut Output amount
    function _calculateOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        uint256 priceIn = oracle.getAssetPrice(tokenIn);
        uint256 priceOut = oracle.getAssetPrice(tokenOut);

        require(priceIn > 0 && priceOut > 0, "Invalid prices");

        uint8 decimalsIn = _getDecimals(tokenIn);
        uint8 decimalsOut = _getDecimals(tokenOut);

        // amountOut = amountIn * priceIn / priceOut, adjusted for decimals
        amountOut = (amountIn * priceIn * (10 ** decimalsOut)) / (priceOut * (10 ** decimalsIn));
    }

    /// @notice Calculate input amount needed for exact output
    /// @dev Applies a 0.5% pool-rate discount to simulate AMM pricing dynamics.
    ///      Real AMM pools quote slightly different from oracle mid-price due to
    ///      pool state, fees, and price impact. This discount ensures the
    ///      protocol's slippage buffer (applied externally in SwapLogic) doesn't
    ///      push the required amount above available funds.
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountOut Desired output amount
    /// @return amountIn Required input amount
    function _calculateInput(address tokenIn, address tokenOut, uint256 amountOut)
        internal
        view
        returns (uint256 amountIn)
    {
        uint256 priceIn = oracle.getAssetPrice(tokenIn);
        uint256 priceOut = oracle.getAssetPrice(tokenOut);

        require(priceIn > 0 && priceOut > 0, "Invalid prices");

        uint8 decimalsIn = _getDecimals(tokenIn);
        uint8 decimalsOut = _getDecimals(tokenOut);

        // amountIn = amountOut * priceOut / priceIn, adjusted for decimals (floor division)
        amountIn = (amountOut * priceOut * (10 ** decimalsIn)) / (priceIn * (10 ** decimalsOut));

        // Apply 0.5% pool-rate discount (simulates favorable AMM execution vs oracle mid-price)
        amountIn = (amountIn * 9950) / 10000;
    }

    /// @notice Get token decimals with fallback to 18
    /// @param token The token address
    /// @return decimals The token decimals
    function _getDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }
}

/// @notice Interface for ERC20 metadata
interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
