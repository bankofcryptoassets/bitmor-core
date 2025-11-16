// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Errors library
 * @notice Defines the error messages emitted by the different contracts of the Bitmor Protocol
 */
library Errors {
  error ZeroAmount();
  error ZeroAddress();
  error LoanDoesNotExists();
  error LoanIsNotActive();
  error InsufficientAmountSuppliedForClosure(uint256 amountRequired, uint256 amountSupplied);
  error IndexOutOfBounds();
  error InvalidAssetPrice();
  error CallerIsNotAAVEPool();
  error WrongFLInitiator();
  error LessThanMinimumAmtReceived();
  error UnauthorizedCaller();
}
