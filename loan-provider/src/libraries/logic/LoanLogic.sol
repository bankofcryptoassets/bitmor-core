// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";

import {ILoan} from "../../interfaces/ILoan.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ILoanVaultFactory} from "../../interfaces/ILoanVaultFactory.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IReserveInterestRateStrategy} from "../../interfaces/IReserveInterestRateStrategy.sol";

import {Errors} from "../helpers/Errors.sol";
import {LoanMath} from "../helpers/LoanMath.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {AavePoolLogic} from "./AavePoolLogic.sol";

/**
 * @title LoanLogic
 * @author Bitmor Protocol
 * @notice Library for loan initialization and calculation logic
 * @dev Handles loan creation, state updates, and delegates math to LoanMath.
 *
 * ## Responsibilities
 * - Validating loan parameters (collateral bounds, deposit requirements)
 * - Computing loan amounts and monthly payments based on oracle prices
 * - Creating Loan Vaults (LSAs) via factory
 * - Initiating flash loans for loan funding
 * - Managing loan state updates for liquidations
 *
 * ## Integration Points
 * - Bitmor Lending Pool for interest rate data
 * - Price Oracle for asset valuations
 * - LoanVaultFactory for LSA creation
 * - Aave V3 for flash loans
 */
library LoanLogic {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /**
     * @notice Executes the full loan initialization flow
     * @dev Creates LSA, stores loan data, transfers funds, and initiates flash loan
     *
     * ## Execution Steps
     * 1. Validates deposit, collateral, and duration parameters
     * 2. Calculates loan amount and monthly payment based on oracle prices
     * 3. Deploys LSA via `LoanVaultFactory` using CREATE2
     * 4. Stores loan data in `loansByLSA` mapping
     * 5. Updates user loan indexing for multi-loan support
     * 6. Transfers deposit from user and premium to collector
     * 7. Initiates flash loan from Aave V3
     *
     * @param loansByLSA Storage mapping of loans by LSA address
     * @param userLoanCount Storage mapping of loan counts per user
     * @param userLoanAtIndex Storage mapping of LSA addresses by user and index
     * @param ctx Context containing protocol addresses and configuration
     * @param params Parameters for loan initialization
     * @return lsa The address of the created Loan Specific Address
     */
    function executeInitializeLoan(
        mapping(address => DataTypes.LoanData) storage loansByLSA,
        mapping(address => uint256) storage userLoanCount,
        mapping(address => mapping(uint256 => address)) storage userLoanAtIndex,
        DataTypes.InitializeLoanContext memory ctx,
        DataTypes.ExecuteInitializeLoanParams memory params
    ) internal returns (address lsa) {
        if (params.depositAmount == 0 || params.collateralAmount == 0) {
            revert Errors.ZeroAmount();
        }

        if (params.duration == 0 || params.duration > ctx.maxDuration) {
            revert Errors.Loan__InvalidDuration();
        }

        if (params.collateralAmount < ctx.minCollateralAmt) {
            revert Errors.LessThanMinimumCollateralAllowed();
        }

        if (params.collateralAmount > ctx.maxCollateralAmt) {
            revert Errors.GreaterThanMaxCollateralAllowed();
        }

        (uint256 loanAmount, uint256 monthlyPayment,) = _calculateLoanAmountAndMonthlyPayment(
            DataTypes.CalculateLoanAmountAndMonthlyPayment(
                ctx.bitmorPool,
                ctx.oracle,
                ctx.collateralAsset,
                ctx.debtAsset,
                params.depositAmount,
                IERC20Metadata(ctx.debtAsset).decimals(),
                params.collateralAmount,
                IERC20Metadata(ctx.collateralAsset).decimals(),
                params.duration,
                ctx.minDepositBps
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
            amountRepaidInCurrentPeriod: 0,
            status: DataTypes.LoanStatus.Active
        });

        // Update user loan indexing for multi-loan support
        uint256 loanIndex = userLoanCount[params.user];
        userLoanAtIndex[params.user][loanIndex] = lsa;
        userLoanCount[params.user] = loanIndex + 1;

        /// @dev Snapshot balance before deposit+flash loan to refund exactOut swap surplus
        uint256 balBefore = IERC20(ctx.debtAsset).balanceOf(address(this));

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

        /// @dev Refund any USDC surplus from the exactOut swap to the user.
        /// The swap consumes at most `deposit + loanAmount` but typically less,
        /// leaving a surplus that belongs to the depositing user.
        uint256 surplus = IERC20(ctx.debtAsset).balanceOf(address(this)) - balBefore;
        if (surplus > 0) IERC20(ctx.debtAsset).safeTransfer(params.user, surplus);

        // Emit loan creation event
        emit ILoan.Loan__LoanCreated(params.user, lsa, loanAmount, params.collateralAmount, params.data);
        return lsa;
    }

    /**
     * @notice Updates the insurance ID for a specific loan
     * @dev Called after insurance is confirmed for a loan
     * @param loansByLSA Storage mapping of loans by LSA address
     * @param lsa The Loan Specific Address
     * @param insuranceID The new insurance ID to set
     */
    function updateInsuranceId(
        mapping(address => DataTypes.LoanData) storage loansByLSA,
        address lsa,
        uint256 insuranceID
    ) internal {
        loansByLSA[lsa].insuranceID = insuranceID;
    }

    /**
     * @notice Updates loan data after a micro-liquidation event
     * @dev Reduces duration by 1 month and updates payment timestamp.
     * Micro-liquidation occurs when a monthly payment is missed and the protocol
     * liquidates one month's worth of collateral.
     * @param loansByLSA Storage mapping of loans by LSA address
     * @param lsa The Loan Specific Address being liquidated
     * @return newDuration The remaining loan duration after deduction
     */
    function updateLoanDataForMicroLiquidation(mapping(address => DataTypes.LoanData) storage loansByLSA, address lsa)
        internal
        returns (uint256 newDuration)
    {
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        newDuration = loan.duration.zeroFloorSub(1);

        loan.duration = newDuration;
        loan.lastPaymentTimestamp = block.timestamp;
    }

    /**
     * @notice Completes the loan after the final micro-liquidation when `duration == 1`
     * @dev Sets `duration` to 0, updates `lastPaymentTimestamp`, and marks `status` as `Completed`.
     * Called by the lending pool when the last remaining period is micro-liquidated,
     * after which remaining collateral is returned to the borrower.
     * @param loansByLSA Storage mapping of loans by LSA address
     * @param lsa The Loan Specific Address being completed
     */
    function updateLoanForMicroLiquidationCompletion(
        mapping(address => DataTypes.LoanData) storage loansByLSA,
        address lsa
    ) internal {
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        loan.duration = 0;
        loan.lastPaymentTimestamp = block.timestamp;
        loan.status = DataTypes.LoanStatus.Completed;
    }

    /**
     * @notice Updates loan data after a full liquidation event
     * @dev Sets duration to 0 and status to Liquidated.
     * Full liquidation occurs when collateral value drops below debt threshold.
     * @param loansByLSA Storage mapping of loans by LSA address
     * @param lsa The Loan Specific Address being liquidated
     */
    function updateLoanDataForFullLiquidation(mapping(address => DataTypes.LoanData) storage loansByLSA, address lsa)
        internal
    {
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        loan.duration = 0;
        loan.lastPaymentTimestamp = block.timestamp;
        loan.status = DataTypes.LoanStatus.Liquidated;
    }

    /**
     * @notice Calculates loan amount and monthly payment by fetching current rates from the Bitmor Lending Pool
     * @dev Fetches oracle prices for both assets and the maximum variable borrow rate from the
     * reserve's interest rate strategy. Delegates the actual math to `LoanMath.calculateLoanAmt`.
     * @param data Parameters containing pool, oracle, asset addresses, amounts, and duration
     * @return exactLoanAmt Calculated loan amount in debt asset decimals (6 for USDC)
     * @return monthlyPayAmt Estimated monthly payment in debt asset decimals
     * @return minDepositRequired Minimum deposit required in debt asset decimals
     */
    function _calculateLoanAmountAndMonthlyPayment(DataTypes.CalculateLoanAmountAndMonthlyPayment memory data)
        internal
        view
        returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        // Get oracle prices
        IPriceOracleGetter oracle = IPriceOracleGetter(data.oracle);
        uint256 collateralPriceUSD = oracle.getAssetPrice(data.collateralAsset);
        uint256 debtPriceUSD = oracle.getAssetPrice(data.debtAsset);

        if (collateralPriceUSD == 0 || debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        // Fetch max variable borrow rate from interest rate strategy
        DataTypes.ReserveData memory reserveData = ILendingPool(data.bitmorPool).getReserveData(data.debtAsset);

        uint256 maxInterestRate =
            IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress).getMaxVariableBorrowRate();

        // Calculate loan amount and monthly payment using fetched rate
        (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanAmt(
            DataTypes.CalculateLoanAmt(
                data.depositAmount,
                data.debtAssetDecimals,
                data.collateralAmount,
                data.collateralAssetDecimals,
                collateralPriceUSD,
                debtPriceUSD,
                maxInterestRate,
                data.duration,
                data.minDepositBps
            )
        );
    }

    /**
     * @notice Calculates loan details for a given collateral amount and duration
     * @dev Used by `Loan.getLoanDetails()` to preview loan terms before creation.
     * Fetches current oracle prices and interest rates to compute values.
     * @param ctx Context containing collateral bounds and minimum deposit BPS
     * @param bitmorPool Bitmor Lending Pool address for interest rate data
     * @param _oracle Price oracle address for asset valuations
     * @param collateralAsset Collateral asset address (cbBTC)
     * @param debtAsset Debt asset address (USDC)
     * @param collateralAmount Amount of collateral (8 decimals for cbBTC)
     * @param duration Loan duration in months
     * @return exactLoanAmt The loan amount in debt asset (6 decimals for USDC)
     * @return monthlyPayAmt The estimated monthly payment (6 decimals)
     * @return minDepositRequired The minimum deposit required (6 decimals)
     */
    function calculateLoanDetails(
        DataTypes.CalculateLoanDetailsContext memory ctx,
        address bitmorPool,
        address _oracle,
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 duration
    ) internal view returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired) {
        if (collateralAmount < ctx.minBTCAmt) revert Errors.LessThanMinimumCollateralAllowed();
        if (collateralAmount > ctx.maxBTCAmt) revert Errors.GreaterThanMaxCollateralAllowed();
        if (duration == 0 || duration > ctx.maxDuration) revert Errors.Loan__InvalidDuration();

        // Get oracle prices
        IPriceOracleGetter oracle = IPriceOracleGetter(_oracle);
        uint256 collateralPriceUSD = oracle.getAssetPrice(collateralAsset);
        uint256 debtPriceUSD = oracle.getAssetPrice(debtAsset);

        if (collateralPriceUSD == 0 || debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        // Fetch max variable borrow rate from interest rate strategy (matches executeInitializeLoan)
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
        uint256 interestRate =
            IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress).getMaxVariableBorrowRate();

        // Calculate loan amount and monthly payment using fetched rate
        (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanDetails(
            collateralAmount,
            collateralPriceUSD,
            IERC20Metadata(collateralAsset).decimals(),
            debtPriceUSD,
            IERC20Metadata(debtAsset).decimals(),
            interestRate,
            duration,
            ctx.minDepositBps
        );
    }
}
