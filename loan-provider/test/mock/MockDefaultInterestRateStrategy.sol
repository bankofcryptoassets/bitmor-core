// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title MockDefaultInterestRateStrategy
/// @notice Interest rate strategy for BTC reserve using aToken balance as liquidity
/// @dev Uses real utilization-based rate calculation matching production behavior
contract MockDefaultInterestRateStrategy is IReserveInterestRateStrategy {
    uint256 public constant RAY = 1e27;

    uint256 public OPTIMAL_UTILIZATION_RATE = 0.8e27; // 80%
    uint256 public EXCESS_UTILIZATION_RATE = 0.2e27; // 20%

    uint256 internal _baseVariableBorrowRate = 0.02e27; // 2%
    uint256 internal _variableRateSlope1 = 0.04e27; // 4%
    uint256 internal _variableRateSlope2 = 0.75e27; // 75%
    uint256 internal _stableRateSlope1 = 0.02e27;
    uint256 internal _stableRateSlope2 = 0.6e27;

    address public addressesProvider;

    constructor(address _addressesProvider) {
        addressesProvider = _addressesProvider;
    }

    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
    }

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

    function setOptimalUtilizationRate(uint256 rate) external {
        OPTIMAL_UTILIZATION_RATE = rate;
        EXCESS_UTILIZATION_RATE = RAY - rate;
    }

    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }

    function setVariableRateSlope1(uint256 rate) external {
        _variableRateSlope1 = rate;
    }

    function setVariableRateSlope2(uint256 rate) external {
        _variableRateSlope2 = rate;
    }
}
