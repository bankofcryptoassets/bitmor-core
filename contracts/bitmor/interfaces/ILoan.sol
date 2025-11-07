// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {DataTypes} from '../libraries/types/DataTypes.sol';

interface ILoan {
  // ============ Events ============

  event Loan__LoanCreated(
    address indexed borrower,
    address indexed lsa,
    uint256 loanAmount,
    uint256 collateralAmount,
    uint256 createdAt
  );

  event Loan__LoanStatusUpdated(
    address indexed lsa,
    DataTypes.LoanStatus oldStatus,
    DataTypes.LoanStatus newStatus
  );

  event Loan__MaxLoanAmountUpdated(uint256 oldAmount, uint256 newAmount);

  event Loan__CollateralWithdrawn(
    address indexed lsa,
    address indexed borrower,
    uint256 amount,
    uint256 timestamp
  );

  event Loan__LoanVaultFactoryUpdated(address indexed oldFactory, address indexed newFactory);

  event Loan__EscrowUpdated(address indexed oldEscrow, address indexed newEscrow);

  event Loan__SwapAdapterUpdated(address indexed oldSwapAdapter, address indexed newSwapAdapter);

  event Loan__ZQuoterUpdated(address indexed oldZQuoter, address indexed newZQuoter);

  event Loan__LoanRepaid(address lsa, uint256 amountRepaid, uint256 nextDueTimestamp);

  event Loan__LoanDataUpdated(address indexed lsa, uint256 timestamp);

  function initializeLoan(
    uint256 depositAmount,
    uint256 collateralAmount,
    uint256 duration,
    uint256 insuranceID
  ) external returns (address lsa);

  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool);

  function getLoanByLSA(address lsa) external view returns (DataTypes.LoanData memory);

  function getUserLoanCount(address user) external view returns (uint256);

  function getUserLoanAtIndex(address user, uint256 index) external view returns (address);

  function getUserAllLoans(address user) external view returns (DataTypes.LoanData[] memory);

  function getCollateralAsset() external view returns (address);

  function getDebtAsset() external view returns (address);

  function calculateStrikePrice(
    uint256 loanAmount,
    uint256 deposit
  ) external view returns (uint256);

  function withdrawCollateral(
    address lsa,
    uint256 amount
  ) external returns (uint256 amountWithdrawn);

  function setMaxLoanAmount(uint256 newMaxLoanAmount) external;

  function setLoanVaultFactory(address newFactory) external;

  function setEscrow(address newEscrow) external;

  function setSwapAdapter(address newSwapAdapter) external;

  function setZQuoter(address newZQuoter) external;

  function updateLoanStatus(address lsa, DataTypes.LoanStatus newStatus) external;

  function updateLoanData(bytes calldata _data, address _lsa) external;
}
