// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

library LoanMath {
  uint256 private constant PRICE_PRECISION = 1e8; // Oracle prices use 8 decimals
  uint256 private constant USDC_DECIMALS = 1e6; // USDC has 6 decimals
  uint256 private constant RAY = 1e27; // Ray precision (27 decimals)
  uint256 private constant PERCENTAGE_FACTOR = 1e4; // For percentage calculations (100.00%)
  uint256 private constant MONTHS_PER_YEAR = 12;

  /**
   * @notice Calculates power of a number with fixed-point precision using RAY
   * @dev Implements exponentiation by squaring for (base)^exponent
   * @param base The base number in RAY precision (27 decimals)
   * @param exponent The exponent (whole number)
   * @return result The result in RAY precision
   */
  function rayPow(uint256 base, uint256 exponent) internal pure returns (uint256 result) {
    result = RAY;

    if (exponent == 0) {
      return result;
    }

    uint256 tempBase = base;
    uint256 tempExponent = exponent;

    // Exponentiation by squaring
    while (tempExponent > 0) {
      if (tempExponent & 1 != 0) {
        result = (result * tempBase) / (RAY);
      }
      tempBase = (tempBase * tempBase) / (RAY);
      tempExponent >>= 1;
    }

    return result;
  }

  /**
   * @notice Calculates the loan amount and monthly payment based on collateral and deposit
   * @dev TODO: Please verify this logic.
   * @dev Uses SafeMath for all calculations to prevent overflow/underflow
   * @param depositAmount User's deposit in USDC (6 decimals)
   * @param collateralAmount Desired BTC collateral amount (8 decimals)
   * @param collateralPriceUSD BTC price in USD (8 decimals from oracle)
   * @param debtPriceUSD USDC price in USD (8 decimals from oracle)
   * @param maxLoanAmount Maximum acceptable loan amount in USDC (6 decimals)
   * @param interestRate Interest rate from Aave V2 reserve (27 decimals - ray)
   * @param duration Loan duration in months
   * @return loanAmount The calculated loan amount in USDC (6 decimals)
   * @return monthlyPayAmt The monthly payment amount in USDC (6 decimals)
   */
  function calculateLoanAmt(
    uint256 depositAmount,
    uint256 collateralAmount,
    uint256 collateralPriceUSD,
    uint256 debtPriceUSD,
    uint256 maxLoanAmount,
    uint256 interestRate,
    uint256 duration
  ) internal pure returns (uint256 loanAmount, uint256 monthlyPayAmt) {
    require(collateralPriceUSD > 0, 'LoanMath: invalid collateral price');
    require(debtPriceUSD > 0, 'LoanMath: invalid debt price');

    // Convert collateral amount to USD value
    // collateralValueUSD = (collateralAmount * collateralPriceUSD) / PRICE_PRECISION
    uint256 collateralValueUSD = (collateralAmount * collateralPriceUSD) / PRICE_PRECISION;

    // Convert deposit amount to USD value
    // depositValueUSD = (depositAmount * debtPriceUSD) / USDC_DECIMALS
    uint256 depositValueUSD = (depositAmount * debtPriceUSD) / USDC_DECIMALS;

    // Ensure collateral value exceeds deposit
    require(collateralValueUSD > depositValueUSD, 'LoanMath: insufficient collateral');

    // Calculate loan amount in USD
    // loanValueUSD = collateralValueUSD - depositValueUSD
    uint256 loanValueUSD = collateralValueUSD - depositValueUSD;

    // Convert loan value back to USDC
    // loanAmount = (loanValueUSD * USDC_DECIMALS) / debtPriceUSD
    loanAmount = (loanValueUSD * USDC_DECIMALS) / debtPriceUSD;

    // Ensure loan doesn't exceed maximum limit
    require(loanAmount <= maxLoanAmount, 'LoanMath: loan amount exceeds maximum');

    // Calculate monthly payment using EMI formula: EMI = P × r × (1 + r)^n / ((1 + r)^n - 1)
    require(duration > 0, 'LoanMath: invalid duration');

    // Handle zero interest rate case (simple division)
    if (interestRate == 0) {
      monthlyPayAmt = loanAmount / duration;
      return (loanAmount, monthlyPayAmt);
    }

    // Convert annual interest rate (ray) to monthly interest rate (ray)
    // monthlyRate = interestRate / 12
    uint256 monthlyRate = interestRate / MONTHS_PER_YEAR;

    // Calculate (1 + r) in RAY precision
    // onePlusRate = RAY + monthlyRate
    uint256 onePlusRate = RAY + monthlyRate;

    // Calculate (1 + r)^n using rayPow
    uint256 onePlusRatePowN = rayPow(onePlusRate, duration);

    // Calculate numerator: P × r × (1 + r)^n
    // First: loanAmount × monthlyRate (result in ray precision)
    uint256 numerator = (loanAmount * monthlyRate) / RAY;
    // Then: multiply by (1 + r)^n
    numerator = (numerator * onePlusRatePowN) / RAY;

    // Calculate denominator: (1 + r)^n - 1
    uint256 denominator = onePlusRatePowN - RAY;

    // Calculate EMI: numerator / denominator
    monthlyPayAmt = (numerator * RAY) / denominator;

    return (loanAmount, monthlyPayAmt);
  }
}
