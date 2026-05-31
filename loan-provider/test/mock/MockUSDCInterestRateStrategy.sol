// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title MockUSDCInterestRateStrategy
/// @author Bitmor Protocol
/// @notice Interest rate strategy for USDC using USDCVault.totalAssets() as liquidity source
/// @dev Unlike the default strategy that uses aToken balance, this strategy queries
///      the USDCVault's `totalAssets()` for available liquidity. Uses a two-slope
///      utilization model with configurable parameters for testing.
contract MockUSDCInterestRateStrategy is IReserveInterestRateStrategy {
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

    /// @notice Address of the USDC vault used as liquidity source
    address public usdcVault;

    /// @notice Creates a new MockUSDCInterestRateStrategy
    /// @param _addressesProvider Address of the lending pool addresses provider
    /// @param _usdcVault Address of the USDC vault for liquidity queries
    constructor(address _addressesProvider, address _usdcVault) {
        addressesProvider = _addressesProvider;
        usdcVault = _usdcVault;
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
        address,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256,
        uint256
    ) public view override returns (uint256, uint256, uint256) {
        return _calculateRates(availableLiquidity, totalStableDebt, totalVariableDebt);
    }

    /// @inheritdoc IReserveInterestRateStrategy
    /// @dev Uses `USDCVault.totalAssets()` as the liquidity source instead of aToken balance
    function calculateInterestRates(
        address,
        address,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256,
        uint256
    ) external view override returns (uint256, uint256, uint256) {
        // KEY DIFFERENCE: Use USDCVault.totalAssets() as liquidity source
        uint256 availableLiquidity = IERC4626(usdcVault).totalAssets();
        availableLiquidity = availableLiquidity + liquidityAdded - liquidityTaken;

        return _calculateRates(availableLiquidity, totalStableDebt, totalVariableDebt);
    }

    /// @dev Calculates interest rates using a two-slope utilization model
    /// @param availableLiquidity Total available liquidity
    /// @param totalStableDebt Total stable debt outstanding
    /// @param totalVariableDebt Total variable debt outstanding
    /// @return liquidityRate The liquidity rate in RAY
    /// @return stableBorrowRate The stable borrow rate in RAY
    /// @return variableBorrowRate The variable borrow rate in RAY
    function _calculateRates(uint256 availableLiquidity, uint256 totalStableDebt, uint256 totalVariableDebt)
        internal
        view
        returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate)
    {
        uint256 totalDebt = totalStableDebt + totalVariableDebt;

        if (totalDebt == 0) {
            return (0, 0.03e27, _baseVariableBorrowRate);
        }

        uint256 utilizationRate = (totalDebt * RAY) / (availableLiquidity + totalDebt);

        if (utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessRatio = ((utilizationRate - OPTIMAL_UTILIZATION_RATE) * RAY) / EXCESS_UTILIZATION_RATE;
            stableBorrowRate = 0.03e27 + _stableRateSlope1 + ((_stableRateSlope2 * excessRatio) / RAY);
            variableBorrowRate =
                _baseVariableBorrowRate + _variableRateSlope1 + ((_variableRateSlope2 * excessRatio) / RAY);
        } else {
            uint256 utilizationRatio = (utilizationRate * RAY) / OPTIMAL_UTILIZATION_RATE;
            stableBorrowRate = 0.03e27 + ((_stableRateSlope1 * utilizationRatio) / RAY);
            variableBorrowRate =
                _baseVariableBorrowRate + ((utilizationRate * _variableRateSlope1) / OPTIMAL_UTILIZATION_RATE);
        }

        liquidityRate = (variableBorrowRate * utilizationRate) / RAY;

        return (liquidityRate, stableBorrowRate, variableBorrowRate);
    }

    // ============ Test Helpers ============

    /// @notice Set the USDC vault address (test helper)
    /// @param _vault New USDC vault address
    function setUSDCVault(address _vault) external {
        usdcVault = _vault;
    }

    /// @notice Set the base variable borrow rate (test helper)
    /// @param rate New base rate in RAY (e.g., 0.02e27 for 2%)
    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }

    /// @notice Set the optimal utilization rate and auto-update excess rate (test helper)
    /// @param rate New optimal utilization rate in RAY (e.g., 0.8e27 for 80%)
    function setOptimalUtilizationRate(uint256 rate) external {
        OPTIMAL_UTILIZATION_RATE = rate;
        EXCESS_UTILIZATION_RATE = RAY - rate;
    }
}
