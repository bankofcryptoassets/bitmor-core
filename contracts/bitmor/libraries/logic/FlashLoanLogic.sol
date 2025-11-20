// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;
import {DataTypes} from '../types/DataTypes.sol';
import {LSALogic} from './LSALogic.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {BitmorLendingPoolLogic} from './BitmorLendingPoolLogic.sol';
import {SwapLogic} from './SwapLogic.sol';
import {Errors} from '../helpers/Errors.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';

library FlashLoanLogic {
  using SafeERC20 for IERC20;

  struct LocalVarsCloseLoan {
    address lsa;
    bool withdrawInCollateralAsset;
    uint256 preClosureFee;
    uint256 finalAmountRepaid;
    uint256 collateralAmountWithdrawn;
    uint256 totalDebtRemaining;
    uint256 collateralAmountToSwap;
    uint256 minimumAcceptable;
    uint256 debtAssetAmtReceived;
    uint256 totalFlashLoanBorrowedAmt;
  }

  function executeFLOperationInitiailizingLoan(
    DataTypes.ExecuteFLOperationContext memory ctx,
    DataTypes.ExecuteFLOperationParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal {
    if (msg.sender != ctx.aavePool) revert Errors.CallerIsNotAAVEPool();
    if (params.initiator != address(this)) revert Errors.WrongFLInitiator();

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

    (address lsa, uint256 collateralAmount) = abi.decode(params.params, (address, uint256));

    // Retrieve loan data from storage
    DataTypes.LoanData storage loan = loansByLSA[lsa];

    uint256 totalSwapAmount = loan.depositAmount + params.amount;

    uint256 minimumAcceptable = SwapLogic.calculateMinBTCAmt(
      ctx.zQuoter,
      ctx.debtAsset, // tokenIn
      ctx.collateralAsset, // tokenOut
      ctx.oracle,
      totalSwapAmount, // amountIn
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

    uint256 borrowAmount = params.amount + params.premium;

    LSALogic.approveCreditDelegation(
      lsa,
      ctx.bitmorPool,
      ctx.debtAsset,
      borrowAmount,
      address(this) // Protocol is the delegatee
    );

    // Approve Aave V2 pool to spend asset
    IERC20(ctx.collateralAsset).forceApprove(ctx.bitmorPool, amountReceived);

    BitmorLendingPoolLogic.depositCollateral(
      ctx.bitmorPool,
      ctx.collateralAsset,
      amountReceived,
      lsa
    );

    BitmorLendingPoolLogic.borrowDebt(ctx.bitmorPool, ctx.debtAsset, borrowAmount, lsa);

    // To allow aavePool to withdraw borrow amount
    IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, borrowAmount);
  }

  function executeFLOperationCloseLoan(
    DataTypes.ExecuteFLOperationContext memory ctx,
    DataTypes.ExecuteFLOperationParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal {
    if (msg.sender != ctx.aavePool) revert Errors.CallerIsNotAAVEPool();
    if (params.initiator != address(this)) revert Errors.WrongFLInitiator();

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan
    LocalVarsCloseLoan memory vars;

    (
      vars.lsa,
      vars.withdrawInCollateralAsset,
      vars.collateralAmountToSwap,
      vars.preClosureFee
    ) = abi.decode(params.params, (address, bool, uint256, uint256));

    // Retrieve loan data from storage
    DataTypes.LoanData storage loan = loansByLSA[vars.lsa];

    // =========== Close Loan ==========
    IERC20(ctx.debtAsset).forceApprove(ctx.bitmorPool, params.amount);

    vars.finalAmountRepaid = BitmorLendingPoolLogic.executeLoanRepayment(
      ctx.bitmorPool,
      ctx.debtAsset,
      vars.lsa,
      params.amount
    );
    // ===============================================================

    // =========== Withdraw collateral asset ==========

    vars.totalDebtRemaining = BitmorLendingPoolLogic.getVDTTokenAmount(
      ctx.bitmorPool,
      ctx.debtAsset,
      vars.lsa
    );
    if (vars.totalDebtRemaining == 0) {
      loan.status = DataTypes.LoanStatus.Completed;
      loan.duration = 0;

      vars.collateralAmountWithdrawn = LSALogic.withdrawCollateral(
        ctx.bitmorPool,
        vars.lsa,
        ctx.collateralAsset,
        address(this)
      );

      if (vars.collateralAmountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();
    }
    // ===============================================================

    // Sends the pre-closure fee to the fee collector
    IERC20(ctx.collateralAsset).safeTransfer(ctx.feeCollector, vars.preClosureFee);

    // =========== Swap the required amount to debt asset ==========

    if (!vars.withdrawInCollateralAsset) {
      // When not withdrawing in collateral asset, swap all remaining after fee
      vars.collateralAmountToSwap = vars.collateralAmountWithdrawn - vars.preClosureFee;
    }
    // When withdrawInCollateralAsset=true, use the amount calculated in CloseLoanLogic

    vars.minimumAcceptable = SwapLogic.calculateMinBTCAmt(
      ctx.zQuoter,
      ctx.collateralAsset, // tokenIn
      ctx.debtAsset, // tokenOut
      ctx.oracle,
      vars.collateralAmountToSwap, // amountIn
      ctx.maxSlippage
    );

    // Approve SwapAdaptor to spend tokens
    IERC20(ctx.collateralAsset).forceApprove(ctx.swapAdapter, vars.collateralAmountToSwap);

    vars.debtAssetAmtReceived = SwapLogic.executeSwap(
      ctx.swapAdapter,
      ctx.collateralAsset, //tokenIn
      ctx.debtAsset, // tokenOut
      vars.collateralAmountToSwap, // amountIn
      vars.minimumAcceptable
    );
    // ===============================================================

    // =========== Send the remaining assets back to the `loan.borrower` ==========
    vars.totalFlashLoanBorrowedAmt = params.amount + params.premium;

    // Send excess debt asset to borrower (if any)
    if (vars.debtAssetAmtReceived > vars.totalFlashLoanBorrowedAmt) {
      IERC20(ctx.debtAsset).safeTransfer(
        loan.borrower,
        vars.debtAssetAmtReceived - vars.totalFlashLoanBorrowedAmt
      );
    }

    // Send remaining collateral to borrower when withdrawing in collateral asset
    if (vars.withdrawInCollateralAsset) {
      uint256 remainingCollateral = vars.collateralAmountWithdrawn -
        vars.collateralAmountToSwap -
        vars.preClosureFee;
      if (remainingCollateral > 0) {
        IERC20(ctx.collateralAsset).safeTransfer(loan.borrower, remainingCollateral);
      }
    }
    // ===============================================================

    // To allow aavePool to withdraw borrow amount
    IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, vars.totalFlashLoanBorrowedAmt);
  }
}
