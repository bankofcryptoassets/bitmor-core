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

    /// @inheritdoc ISwapAdaptor
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bool /* stable */
    )
        external
        override
        returns (uint256 amountOut)
    {
        require(!shouldRevert, "Swap reverted");

        uint256 priceIn = oracle.getAssetPrice(tokenIn);
        uint256 priceOut = oracle.getAssetPrice(tokenOut);

        require(priceIn > 0 && priceOut > 0, "Invalid prices");

        uint8 decimalsIn = _getDecimals(tokenIn);
        uint8 decimalsOut = _getDecimals(tokenOut);

        // Calculate output: amountIn * priceIn / priceOut, adjusted for decimals
        amountOut = (amountIn * priceIn * (10 ** decimalsOut)) / (priceOut * (10 ** decimalsIn));

        // Apply slippage
        if (slippageBps > 0) {
            amountOut = (amountOut * (10000 - slippageBps)) / 10000;
        }

        require(amountOut >= minAmountOut, "Slippage exceeded");

        // Execute transfer
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        emit Swap(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Fund the adapter with tokens for swaps
    /// @param token The token to fund
    /// @param amount The amount to fund
    function fund(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ISwapAdaptor
    function swapExactTokensForTokensCL(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        int24 /* tickSpacing */
    ) external override returns (uint256 amountOut) {
        // Delegate to standard swap (mock doesn't distinguish CL pools)
        return this.swapExactTokensForTokens(tokenIn, tokenOut, amountIn, minAmountOut, false);
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
