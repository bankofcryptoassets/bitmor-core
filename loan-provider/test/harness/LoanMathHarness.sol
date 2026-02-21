// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanMath} from "@bitmor/libraries/helpers/LoanMath.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanMathHarness
 * @author Bitmor Protocol
 * @notice Harness contract to expose internal LoanMath functions for fuzz testing
 * @dev Wraps library functions as external calls for direct testing
 */
contract LoanMathHarness {
    /**
     * @notice Exposes LoanMath.rayPow for testing
     * @param base The base number in RAY precision (27 decimals)
     * @param exponent The exponent (whole number, not RAY-scaled)
     * @return The result in RAY precision
     */
    function exposed_rayPow(uint256 base, uint256 exponent) external pure returns (uint256) {
        return LoanMath.rayPow(base, exponent);
    }

    /**
     * @notice Exposes LoanMath.calculateLoanAmt for testing
     * @param data Struct containing all calculation parameters
     * @return loanAmount The calculated loan amount in debt asset decimals
     * @return monthlyPayAmt The monthly payment amount in debt asset decimals
     * @return minDepositRequired Minimum deposit required in debt asset decimals
     */
    function exposed_calculateLoanAmt(DataTypes.CalculateLoanAmt memory data)
        external
        pure
        returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        return LoanMath.calculateLoanAmt(data);
    }

    /**
     * @notice Exposes LoanMath.calculateLoanDetails for testing
     * @param collateralAmount Desired BTC collateral amount (8 decimals)
     * @param collateralPriceUSD BTC price in USD (8 decimals from oracle)
     * @param collateralAssetDecimals Number of decimals for collateral asset
     * @param debtPriceUSD USDC price in USD (8 decimals from oracle)
     * @param debtAssetDecimals Number of decimals for debt asset
     * @param interestRate Interest rate from Aave V2 reserve (27 decimals - RAY)
     * @param duration Loan duration in months
     * @param minDepositBps Minimum deposit in basis points
     * @param flashLoanPremiumBps Aave V3 flash loan premium in basis points
     * @return loanAmount The calculated loan amount in USDC (6 decimals)
     * @return monthlyPayAmt The monthly payment amount in USDC (6 decimals)
     * @return minDepositRequired Minimum deposit required amount in USDC (6 decimals)
     */
    function exposed_calculateLoanDetails(
        uint256 collateralAmount,
        uint256 collateralPriceUSD,
        uint256 collateralAssetDecimals,
        uint256 debtPriceUSD,
        uint256 debtAssetDecimals,
        uint256 interestRate,
        uint256 duration,
        uint256 minDepositBps,
        uint256 flashLoanPremiumBps
    ) external pure returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired) {
        return LoanMath.calculateLoanDetails(
            collateralAmount,
            collateralPriceUSD,
            collateralAssetDecimals,
            debtPriceUSD,
            debtAssetDecimals,
            interestRate,
            duration,
            minDepositBps,
            flashLoanPremiumBps
        );
    }

    /**
     * @notice Exposes LoanMath.calculateStrikePrice for testing
     * @param btcPriceUSD Current BTC price in USD (8 decimals)
     * @param loanAmount The loan amount in debt asset (6 decimals for USDC)
     * @param deposit The deposit amount in debt asset (6 decimals for USDC)
     * @return strikePrice The calculated strike price in USD (8 decimals)
     */
    function exposed_calculateStrikePrice(uint256 btcPriceUSD, uint256 loanAmount, uint256 deposit)
        external
        pure
        returns (uint256)
    {
        return LoanMath.calculateStrikePrice(btcPriceUSD, loanAmount, deposit);
    }

    /**
     * @notice Exposes LoanMath.min for testing
     * @param a The first value
     * @param b The second value
     * @return The minimum of the two values
     */
    function exposed_min(uint256 a, uint256 b) external pure returns (uint256) {
        return LoanMath.min(a, b);
    }
}
