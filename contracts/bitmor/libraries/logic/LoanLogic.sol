// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {LoanMath} from '../helpers/LoanMath.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {ILoanVaultFactory} from '../../interfaces/ILoanVaultFactory.sol';
import {Errors} from '../helpers/Errors.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';
import {BitmorLendingPoolLogic} from '../logic/BitmorLendingPoolLogic.sol';

import {SwapLogic} from '../logic/SwapLogic.sol';
import {LSALogic} from '../logic/LSALogic.sol';

/**
 * @title LoanLogic
 * @notice Library for loan calculation logic
 * @dev Handles fetching prices and interest rates from Aave V2, delegates math to LoanMath
 */
library LoanLogic {
  using SafeERC20 for IERC20;

  function executeInitializeLoan(
    DataTypes.InitializeLoanContext memory ctx,
    DataTypes.ExecuteInitializeLoanParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA,
    mapping(address => uint256) storage userLoanCount,
    mapping(address => mapping(uint256 => address)) storage userLoanAtIndex
  ) internal returns (address lsa) {
    if (params.depositAmount == 0 || params.collateralAmount == 0 || params.duration == 0)
      revert Errors.ZeroAmount();

    (uint256 loanAmount, uint256 monthlyPayment, ) = calculateLoanAmountAndMonthlyPayment(
      ctx.bitmorPool,
      ctx.oracle,
      ctx.collateralAsset,
      ctx.debtAsset,
      params.depositAmount,
      ctx.maxLoanAmt,
      params.collateralAmount,
      params.duration
    );

    // Create LSA via factory using CREATE2 for deterministic address
    lsa = ILoanVaultFactory(ctx.loanVaultFactory).createLoanVault(params.user, block.timestamp);

    // Calculate payment timestamps (30 days = 1 month)
    uint256 firstPaymentDue = block.timestamp + ctx.loanRepaymentInterval;

    // Store loan data on-chain
    loansByLSA[lsa] = DataTypes.LoanData({
      borrower: params.user,
      depositAmount: params.depositAmount,
      loanAmount: loanAmount,
      collateralAmount: params.collateralAmount,
      estimatedMonthlyPayment: monthlyPayment,
      duration: params.duration,
      createdAt: block.timestamp,
      insuranceID: params.insuranceID,
      nextDueTimestamp: firstPaymentDue,
      lastDueTimestamp: 0,
      status: DataTypes.LoanStatus.Active
    });

    // Update user loan indexing for multi-loan support
    uint256 loanIndex = userLoanCount[params.user];
    userLoanAtIndex[params.user][loanIndex] = lsa;
    userLoanCount[params.user] = loanIndex + 1;

    // Transfer deposit from user to contract
    IERC20(ctx.debtAsset).safeTransferFrom(params.user, address(this), params.depositAmount);

    // Transfer premium amount to premium collector
    if (params.premiumAmount > 0) {
      IERC20(ctx.debtAsset).safeTransferFrom(
        params.user,
        ctx.premiumCollector,
        params.premiumAmount
      );
    }

    // Flash loan execution flow
    {
      address[] memory assets = new address[](1);
      assets[0] = ctx.debtAsset;

      uint256[] memory amounts = new uint256[](1);
      amounts[0] = loanAmount;

      uint256[] memory modes = new uint256[](1);
      modes[0] = 0; // don't open any debt, just revert if funds can't be transferred from the receiver

      bytes memory paramsForFL = abi.encode(lsa, params.collateralAmount);

      ILendingPool(ctx.aavePool).flashLoan(
        address(this), // receiver address
        assets, // assets to borrow
        amounts, // amounts to borrow the assets
        modes, // modes of the debt to open if the flash loan is not returned
        lsa, // onbehalf of address
        paramsForFL, // params to pass to the receiver
        uint16(0) // referral code
      );
    }

    // Emit loan creation event
    emit ILoan.Loan__LoanCreated(params.user, lsa, loanAmount, params.collateralAmount);
    return lsa;
  }

  function executeFLOperation(
    DataTypes.FLOperationContext memory ctx,
    DataTypes.FLOperationParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal {
    if (msg.sender != ctx.aavePool) revert Errors.CallerIsNotAAVEPool();
    if (params.initiator != address(this)) revert Errors.WrongFLInitiator();

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

    (address lsa, uint256 collateralAmount) = abi.decode(params.params, (address, uint256));

    // Retrieve loan data from storage
    DataTypes.LoanData storage loan = loansByLSA[lsa];

    uint256 flashLoanAmount = params.amounts[0];
    uint256 flashLoanPremium = params.premiums[0];
    uint256 totalSwapAmount = loan.depositAmount + flashLoanAmount;

    uint256 minimumAcceptable = SwapLogic.calculateMinBTCAmt(
      ctx.zQuoter,
      ctx.debtAsset, // tokenIn
      ctx.collateralAsset, // tokenOut
      totalSwapAmount, // amountIn
      collateralAmount,
      ctx.maxSlippage
    );

    // Approve SwapAdaptor to spend tokens
    IERC20(ctx.debtAsset).forceApprove(ctx.swapAdapter, totalSwapAmount);

    uint256 amountReceived = SwapLogic.executeSwap(
      ctx.swapAdapter,
      ctx.debtAsset,
      ctx.collateralAsset,
      totalSwapAmount,
      minimumAcceptable
    );

    if (amountReceived < minimumAcceptable) revert Errors.LessThanMinimumAmtReceived();

    uint256 borrowAmount = flashLoanAmount + flashLoanPremium;

    LSALogic.approveCreditDelegation(
      lsa,
      ctx.bitmorPool,
      ctx.debtAsset,
      borrowAmount,
      address(this) // Protocol is the delegatee
    );

    BitmorLendingPoolLogic.depositCollateral(
      ctx.bitmorPool,
      ctx.collateralAsset,
      amountReceived,
      lsa
    );

    BitmorLendingPoolLogic.borrowDebt(ctx.bitmorPool, ctx.debtAsset, borrowAmount, lsa);

    IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, borrowAmount);
  }

  /**
   * @notice Calculates loan amount and monthly payment by fetching current rates from Aave V2
   * @dev Fetch oracle price for the assets
   * @param bitmorPool Bitmor Lending Pool address
   * @param _oracle Price Oracle address
   * @param collateralAsset cbBTC address
   * @param debtAsset USDC address
   * @param depositAmount User's USDC deposit (6 decimals)
   * @param maxLoanAmount Maximum allowed loan amount (6 decimals)
   * @param collateralAmount Desired cbBTC collateral (8 decimals)
   * @param duration Loan duration in months
   * @return exactLoanAmt Calculated loan amount in USDC (6 decimals)
   * @return monthlyPayAmt Estimated monthly payment (6 decimals)
   * @return minDepositRequired Minimum deposit requried amount
   */
  function calculateLoanAmountAndMonthlyPayment(
    address bitmorPool,
    address _oracle,
    address collateralAsset,
    address debtAsset,
    uint256 depositAmount,
    uint256 maxLoanAmount,
    uint256 collateralAmount,
    uint256 duration
  )
    internal
    view
    returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired)
  {
    // Get oracle prices
    IPriceOracleGetter oracle = IPriceOracleGetter(_oracle);
    uint256 collateralPriceUSD = oracle.getAssetPrice(collateralAsset);
    uint256 debtPriceUSD = oracle.getAssetPrice(debtAsset);

    // Fetch current variable borrow rate from Aave V2 USDC reserve
    DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);

    uint256 interestRate = reserveData.currentVariableBorrowRate;

    // Calculate loan amount and monthly payment using fetched rate
    (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanAmt(
      depositAmount,
      collateralAmount,
      collateralPriceUSD,
      debtPriceUSD,
      maxLoanAmount,
      interestRate,
      duration
    );
  }

  function calculateLoanDetails(
    address bitmorPool,
    address _oracle,
    address collateralAsset,
    address debtAsset,
    uint256 maxLoanAmount,
    uint256 collateralAmount,
    uint256 duration
  )
    internal
    view
    returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired)
  {
    // Get oracle prices
    IPriceOracleGetter oracle = IPriceOracleGetter(_oracle);
    uint256 collateralPriceUSD = oracle.getAssetPrice(collateralAsset);
    uint256 debtPriceUSD = oracle.getAssetPrice(debtAsset);

    // Fetch current variable borrow rate from Aave V2 USDC reserve
    DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
    uint256 interestRate = reserveData.currentVariableBorrowRate;

    // Calculate loan amount and monthly payment using fetched rate
    (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanDetails(
      collateralAmount,
      collateralPriceUSD,
      debtPriceUSD,
      maxLoanAmount,
      interestRate,
      duration
    );
  }
}
