// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';

library LoanMath {
  using SafeMath for uint256;

  uint256 private constant PRICE_PRECISION = 1e8; // Oracle prices use 8 decimals
  uint256 private constant USDC_DECIMALS = 1e6; // USDC has 6 decimals
  uint256 private constant SECONDS_PER_MONTH = 30 days; // Average seconds per month

  /**
   * @notice Calculates the loan amount and monthly payment based on collateral and deposit
   * @dev TODO: Please verify this logic.
   * @dev Uses SafeMath for all calculations to prevent overflow/underflow
   * @param depositAmount User's deposit in USDC (6 decimals)
   * @param collateralAmount Desired BTC collateral amount (8 decimals)
   * @param collateralPriceUSD BTC price in USD (8 decimals from oracle)
   * @param debtPriceUSD USDC price in USD (8 decimals from oracle)
   * @param maxLoanAmount Maximum acceptable loan amount in USDC (6 decimals)
   * @param interestRate Interest rate from Bonzo reserve (27 decimals - ray)
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
    uint256 collateralValueUSD = collateralAmount.mul(collateralPriceUSD).div(PRICE_PRECISION);

    // Convert deposit amount to USD value
    // depositValueUSD = (depositAmount * debtPriceUSD) / USDC_DECIMALS
    uint256 depositValueUSD = depositAmount.mul(debtPriceUSD).div(USDC_DECIMALS);

    // Ensure collateral value exceeds deposit
    require(collateralValueUSD > depositValueUSD, 'LoanMath: insufficient collateral');

    // Calculate loan amount in USD
    // loanValueUSD = collateralValueUSD - depositValueUSD
    uint256 loanValueUSD = collateralValueUSD.sub(depositValueUSD);

    // Convert loan value back to USDC
    // loanAmount = (loanValueUSD * USDC_DECIMALS) / debtPriceUSD
    loanAmount = loanValueUSD.mul(USDC_DECIMALS).div(debtPriceUSD);

    // Ensure loan doesn't exceed maximum limit
    require(loanAmount <= maxLoanAmount, 'LoanMath: loan amount exceeds maximum');

    // Calculate monthly payment
    // monthlyPayAmt = loanAmount * (100 + interestRate) * SECONDS_PER_MONTH / (duration * 100)
    require(duration > 0, 'LoanMath: invalid duration');
    monthlyPayAmt = loanAmount.mul(uint256(100).add(interestRate)).mul(SECONDS_PER_MONTH).div(
      duration.mul(100)
    );

    return (loanAmount, monthlyPayAmt);
  }
}
