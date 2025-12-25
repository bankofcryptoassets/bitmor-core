// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {LoanMath} from "../helpers/LoanMath.sol";
import {ILoan} from "../../interfaces/ILoan.sol";
import {ILoanVaultFactory} from "../../interfaces/ILoanVaultFactory.sol";
import {Errors} from "../helpers/Errors.sol";
import {IERC20} from "../../dependencies/openzeppelin/IERC20.sol";
import {IERC20Metadata} from "../../dependencies/openzeppelin/IERC20Metadata.sol";
import {SafeERC20} from "../../dependencies/openzeppelin/SafeERC20.sol";
import {AavePoolLogic} from "./AavePoolLogic.sol";

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
        if (params.depositAmount == 0 || params.collateralAmount == 0 || params.duration == 0) {
            revert Errors.ZeroAmount();
        }

        if (params.collateralAmount < ctx.minCollateralAmt) {
            revert Errors.LessThanMinimumCollateralAllowed();
        }

        if (params.collateralAmount > ctx.maxCollateralAmt) {
            revert Errors.GreaterThanMaxCollateralAllowed();
        }

        (uint256 loanAmount, uint256 monthlyPayment,) = calculateLoanAmountAndMonthlyPayment(
            DataTypes.CalculateLoanAmountAndMonthlyPayment(
                ctx.bitmorPool,
                ctx.oracle,
                ctx.collateralAsset,
                ctx.debtAsset,
                params.depositAmount,
                IERC20Metadata(ctx.debtAsset).decimals(),
                params.collateralAmount,
                IERC20Metadata(ctx.collateralAsset).decimals(),
                params.duration
            )
        );

        // Create LSA via factory using CREATE2 for deterministic address
        lsa = ILoanVaultFactory(ctx.loanVaultFactory).createLoanVault(params.user, block.timestamp);

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
            lastPaymentTimestamp: block.timestamp,
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
            IERC20(ctx.debtAsset).safeTransferFrom(params.user, ctx.premiumCollector, params.premiumAmount);
        }

        // Flash loan execution flow
        bool initializingLoan = true;
        bytes memory flData = abi.encode(lsa, params.collateralAmount);
        bytes memory paramsForFL = abi.encode(initializingLoan, flData);

        AavePoolLogic.executeFlashLoan(ctx.aavePool, address(this), ctx.debtAsset, loanAmount, paramsForFL);

        // Emit loan creation event
        emit ILoan.Loan__LoanCreated(params.user, lsa, loanAmount, params.collateralAmount, params.data);
        return lsa;
    }

    /**
     * @notice Calculates loan amount and monthly payment by fetching current rates from Aave V2
     * @dev Fetch oracle price for the assets
     * @param data Params to calculate the loan details based on deposit amount
     * @return exactLoanAmt Calculated loan amount in USDC (6 decimals)
     * @return monthlyPayAmt Estimated monthly payment (6 decimals)
     * @return minDepositRequired Minimum deposit requried amount
     */
    function calculateLoanAmountAndMonthlyPayment(DataTypes.CalculateLoanAmountAndMonthlyPayment memory data)
        internal
        view
        returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        // Get oracle prices
        IPriceOracleGetter oracle = IPriceOracleGetter(data.oracle);
        uint256 collateralPriceUSD = oracle.getAssetPrice(data.collateralAsset);
        uint256 debtPriceUSD = oracle.getAssetPrice(data.debtAsset);

        if (collateralPriceUSD == 0 || debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        // Fetch current variable borrow rate from Aave V2 USDC reserve
        DataTypes.ReserveData memory reserveData = ILendingPool(data.bitmorPool).getReserveData(data.debtAsset);

        uint256 interestRate = reserveData.currentVariableBorrowRate;

        // Calculate loan amount and monthly payment using fetched rate
        (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanAmt(
            DataTypes.CalculateLoanAmt(
                data.depositAmount,
                data.debtAssetDecimals,
                data.collateralAmount,
                data.collateralAssetDecimals,
                collateralPriceUSD,
                debtPriceUSD,
                interestRate,
                data.duration
            )
        );
    }

    function calculateLoanDetails(
        address bitmorPool,
        address _oracle,
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 duration
    ) internal view returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired) {
        // Get oracle prices
        IPriceOracleGetter oracle = IPriceOracleGetter(_oracle);
        uint256 collateralPriceUSD = oracle.getAssetPrice(collateralAsset);
        uint256 debtPriceUSD = oracle.getAssetPrice(debtAsset);

        if (collateralPriceUSD == 0 || debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        // Fetch current variable borrow rate from Aave V2 USDC reserve
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
        uint256 interestRate = reserveData.currentVariableBorrowRate;

        // Calculate loan amount and monthly payment using fetched rate
        (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanDetails(
            collateralAmount,
            collateralPriceUSD,
            IERC20Metadata(collateralAsset).decimals(),
            debtPriceUSD,
            IERC20Metadata(debtAsset).decimals(),
            interestRate,
            duration
        );
    }
}
