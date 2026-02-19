// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title MockDefaultInterestRateStrategy
/// @author Bitmor Protocol
/// @notice Interest rate strategy for BTC reserve using aToken balance as liquidity source
/// @dev Uses a two-slope utilization-based rate calculation matching production behavior.
///      Queries the lending rate oracle for market borrow rates via the addresses provider.
contract MockDefaultInterestRateStrategy is IReserveInterestRateStrategy {
    /// @notice RAY precision constant (1e27) for rate calculations
    uint256 public constant RAY = 1e27;

    /// @notice Optimal utilization rate (default: 80% in RAY)
    uint256 public OPTIMAL_UTILIZATION_RATE = 0.8e27;

    /// @notice Excess utilization rate above optimal (default: 20% in RAY)
    uint256 public EXCESS_UTILIZATION_RATE = 0.2e27;

    /// @dev Base variable borrow rate (default: 2% in RAY)
    uint256 internal _baseVariableBorrowRate = 0.02e27;

    /// @dev Variable rate slope below optimal utilization (default: 4% in RAY)
    uint256 internal _variableRateSlope1 = 0.04e27;

    /// @dev Variable rate slope above optimal utilization (default: 75% in RAY)
    uint256 internal _variableRateSlope2 = 0.75e27;

    /// @dev Stable rate slope below optimal utilization
    uint256 internal _stableRateSlope1 = 0.02e27;

    /// @dev Stable rate slope above optimal utilization
    uint256 internal _stableRateSlope2 = 0.6e27;

    /// @notice Address of the lending pool addresses provider
    address public addressesProvider;

    /// @notice Creates a new MockDefaultInterestRateStrategy
    /// @param _addressesProvider Address of the lending pool addresses provider
    constructor(address _addressesProvider) {
        addressesProvider = _addressesProvider;
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) public view override returns (uint256, uint256, uint256) {
        return _calculateRates(
            reserve, availableLiquidity, totalStableDebt, totalVariableDebt, averageStableBorrowRate, reserveFactor
        );
    }

    /// @inheritdoc IReserveInterestRateStrategy
    /// @dev Uses `reserve` token balance of the `aToken` contract as the liquidity source
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external view override returns (uint256, uint256, uint256) {
        // Key: Use aToken balance as liquidity source
        uint256 availableLiquidity = IERC20(reserve).balanceOf(aToken);
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return _calculateRates(
            reserve, availableLiquidity, totalStableDebt, totalVariableDebt, averageStableBorrowRate, reserveFactor
        );
    }

    /// @dev Calculates interest rates using a two-slope utilization model with market borrow rate
    /// @param reserve The reserve asset address (used to query market borrow rate)
    /// @param availableLiquidity Total available liquidity
    /// @param totalStableDebt Total stable debt outstanding
    /// @param totalVariableDebt Total variable debt outstanding
    /// @return liquidityRate The liquidity rate in RAY
    /// @return stableBorrowRate The stable borrow rate in RAY
    /// @return variableBorrowRate The variable borrow rate in RAY
    function _calculateRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256,
        uint256
    ) internal view returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate) {
        uint256 totalDebt = totalStableDebt + totalVariableDebt;

        if (totalDebt == 0) {
            return (0, _getMarketBorrowRate(reserve), _baseVariableBorrowRate);
        }

        uint256 utilizationRate = (totalDebt * RAY) / (availableLiquidity + totalDebt);

        stableBorrowRate = _getMarketBorrowRate(reserve);

        if (utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessRatio = ((utilizationRate - OPTIMAL_UTILIZATION_RATE) * RAY) / EXCESS_UTILIZATION_RATE;
            stableBorrowRate = stableBorrowRate + _stableRateSlope1 + ((_stableRateSlope2 * excessRatio) / RAY);
            variableBorrowRate =
                _baseVariableBorrowRate + _variableRateSlope1 + ((_variableRateSlope2 * excessRatio) / RAY);
        } else {
            uint256 utilizationRatio = (utilizationRate * RAY) / OPTIMAL_UTILIZATION_RATE;
            stableBorrowRate = stableBorrowRate + ((_stableRateSlope1 * utilizationRatio) / RAY);
            variableBorrowRate =
                _baseVariableBorrowRate + ((utilizationRate * _variableRateSlope1) / OPTIMAL_UTILIZATION_RATE);
        }

        // Simplified liquidity rate calculation
        liquidityRate = (variableBorrowRate * utilizationRate) / RAY;

        return (liquidityRate, stableBorrowRate, variableBorrowRate);
    }

    /// @dev Queries the lending rate oracle for the market borrow rate of `reserve`
    /// @param reserve The reserve asset address
    /// @return The market borrow rate in RAY (defaults to 3% if oracle unavailable)
    function _getMarketBorrowRate(address reserve) internal view returns (uint256) {
        // Use interface to get oracle from addresses provider
        (bool success, bytes memory data) =
            addressesProvider.staticcall(abi.encodeWithSignature("getLendingRateOracle()"));
        if (!success || data.length == 0) return 0.03e27;

        address oracle = abi.decode(data, (address));
        if (oracle == address(0)) return 0.03e27;

        (success, data) = oracle.staticcall(abi.encodeWithSignature("getMarketBorrowRate(address)", reserve));
        if (!success || data.length == 0) return 0.03e27;

        return abi.decode(data, (uint256));
    }

    // ============ Test Helpers ============

    /// @notice Set the optimal utilization rate and auto-update excess rate (test helper)
    /// @param rate New optimal utilization rate in RAY (e.g., 0.8e27 for 80%)
    function setOptimalUtilizationRate(uint256 rate) external {
        OPTIMAL_UTILIZATION_RATE = rate;
        EXCESS_UTILIZATION_RATE = RAY - rate;
    }

    /// @notice Set the base variable borrow rate (test helper)
    /// @param rate New base rate in RAY (e.g., 0.02e27 for 2%)
    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }

    /// @notice Set variable rate slope 1 (test helper)
    /// @param rate New slope1 value in RAY
    function setVariableRateSlope1(uint256 rate) external {
        _variableRateSlope1 = rate;
    }

    /// @notice Set variable rate slope 2 (test helper)
    /// @param rate New slope2 value in RAY
    function setVariableRateSlope2(uint256 rate) external {
        _variableRateSlope2 = rate;
    }
}
