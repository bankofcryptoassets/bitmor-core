// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.6.12;

/**
 * @title IReserveInterestRateStrategy
 * @author Aave
 * @notice Interface for calculating reserve interest rates
 * @dev Used by the Bitmor Lending Pool to determine borrow and supply rates
 */
interface IReserveInterestRateStrategy {
    /// @notice Returns the base variable borrow rate (expressed in RAY).
    function baseVariableBorrowRate() external view returns (uint256);

    /// @notice Returns the maximum variable borrow rate (expressed in RAY).
    function getMaxVariableBorrowRate() external view returns (uint256);

    /**
     * @notice Calculates interest rates given the reserve state
     * @param reserve The reserve address
     * @param availableLiquidity The available liquidity in the reserve
     * @param totalStableDebt The total stable debt
     * @param totalVariableDebt The total variable debt
     * @param averageStableBorrowRate The average stable borrow rate
     * @param reserveFactor The reserve factor
     * @return The liquidity rate, stable borrow rate, and variable borrow rate (all in RAY)
     */
    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external view returns (uint256, uint256, uint256);

    /**
     * @notice Calculates interest rates using aToken address for liquidity changes
     * @param reserve The reserve address
     * @param aToken The aToken address for the reserve
     * @param liquidityAdded The amount of liquidity being added
     * @param liquidityTaken The amount of liquidity being removed
     * @param totalStableDebt The total stable debt
     * @param totalVariableDebt The total variable debt
     * @param averageStableBorrowRate The average stable borrow rate
     * @param reserveFactor The reserve factor
     * @return liquidityRate The calculated liquidity rate (in RAY)
     * @return stableBorrowRate The calculated stable borrow rate (in RAY)
     * @return variableBorrowRate The calculated variable borrow rate (in RAY)
     */
    function calculateInterestRates(
        address reserve,
        address aToken,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external view returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate);
}
