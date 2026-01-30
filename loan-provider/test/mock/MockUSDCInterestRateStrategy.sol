// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";

/// @title MockUSDCInterestRateStrategy
/// @notice Interest rate strategy for USDC using USDCVault.totalAssets() as liquidity
/// @dev Key difference: uses vault's totalAssets instead of aToken balance
contract MockUSDCInterestRateStrategy is IReserveInterestRateStrategy {
    uint256 public constant RAY = 1e27;

    uint256 public OPTIMAL_UTILIZATION_RATE = 0.8e27;
    uint256 public EXCESS_UTILIZATION_RATE = 0.2e27;

    uint256 internal _baseVariableBorrowRate = 0.02e27;
    uint256 internal _variableRateSlope1 = 0.04e27;
    uint256 internal _variableRateSlope2 = 0.75e27;
    uint256 internal _stableRateSlope1 = 0.02e27;
    uint256 internal _stableRateSlope2 = 0.6e27;

    address public addressesProvider;
    address public usdcVault;

    constructor(address _addressesProvider, address _usdcVault) {
        addressesProvider = _addressesProvider;
        usdcVault = _usdcVault;
    }

    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate + _variableRateSlope1 + _variableRateSlope2;
    }

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

    function setUSDCVault(address _vault) external {
        usdcVault = _vault;
    }

    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }

    function setOptimalUtilizationRate(uint256 rate) external {
        OPTIMAL_UTILIZATION_RATE = rate;
        EXCESS_UTILIZATION_RATE = RAY - rate;
    }
}
