// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {ILoan} from "../../interfaces/ILoan.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ILoanVaultFactory} from "../../interfaces/ILoanVaultFactory.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IReserveInterestRateStrategy} from "../../interfaces/IReserveInterestRateStrategy.sol";

import {Errors} from "../helpers/Errors.sol";
import {Constants} from "../helpers/Constants.sol";
import {LoanMath} from "../helpers/LoanMath.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {LoanStorage} from "../../protocol/LoanStorage.sol";

import {LSALogic} from "./LSALogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {AavePoolLogic} from "./AavePoolLogic.sol";

/**
 * @title LoanLogic
 * @author Bitmor Protocol
 * @notice Library for loan initialization and calculation logic
 * @dev Deployed as a linked library (public functions) to reduce Loan.sol bytecode size.
 * Functions that previously accepted storage pointer parameters now receive a `bytes32 storageSlot`
 * and resolve storage internally via ERC-7201 namespaced storage pattern.
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
    using LSALogic for address;
    using BitmorLendingPoolLogic for address;
    using AavePoolLogic for address;

    /// @dev Resolves the LoanStorageData struct from a given ERC-7201 storage slot
    function _resolveStorage(bytes32 slot) private pure returns (LoanStorage.LoanStorageData storage $) {
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Executes the full loan initialization flow
     * @dev Creates LSA, stores loan data, transfers funds, and initiates flash loan.
     * Called via DELEGATECALL from Loan.sol — `msg.sender`, `address(this)` reflect Loan proxy context.
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
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param ctx Context containing protocol addresses and configuration
     * @param params Parameters for loan initialization
     * @return lsa The address of the created Loan Specific Address
     */
    function executeInitializeLoan(
        bytes32 storageSlot,
        DataTypes.InitializeLoanContext memory ctx,
        DataTypes.ExecuteInitializeLoanParams memory params
    ) public returns (address lsa, uint256 loanAmount, uint256 monthlyPayment) {
        if (params.depositAmount == 0 || params.btcAmount == 0) {
            revert Errors.ZeroAmount();
        }

        if (params.duration == 0 || params.duration > ctx.maxDuration) {
            revert Errors.Loan__InvalidDuration();
        }

        if (params.btcAmount < ctx.minBTCAmt) {
            revert Errors.LessThanMinBTCAllowed();
        }

        if (params.btcAmount > ctx.maxBTCAmt) {
            revert Errors.GreaterThanMaxBTCAllowed();
        }

        (loanAmount, monthlyPayment,) = _calculateLoanAmountAndMonthlyPayment(
            DataTypes.CalculateLoanAmountAndMonthlyPayment({
                bitmorPool: ctx.bitmorPool,
                oracle: ctx.oracle,
                btc: ctx.btc,
                debtAsset: ctx.debtAsset,
                aavePool: ctx.aavePool,
                depositAmount: params.depositAmount,
                debtAssetDecimals: IERC20Metadata(ctx.debtAsset).decimals(),
                btcAmount: params.btcAmount,
                btcAssetDecimals: IERC20Metadata(ctx.btc).decimals(),
                duration: params.duration,
                minDepositBps: ctx.minDepositBps
            })
        );

        lsa = ILoanVaultFactory(ctx.loanVaultFactory).createLoanVault(params.user, block.timestamp);

        LoanStorage.LoanStorageData storage $ = _resolveStorage(storageSlot);

        $.loansByLSA[lsa] = DataTypes.LoanData({
            borrower: params.user,
            duration: SafeCast.toUint16(params.duration),
            status: DataTypes.LoanStatus.Active,
            createdAt: SafeCast.toUint32(block.timestamp),
            lastPaymentTimestamp: SafeCast.toUint32(block.timestamp),
            depositAmount: SafeCast.toUint96(params.depositAmount),
            loanAmount: SafeCast.toUint96(loanAmount),
            btcAmount: SafeCast.toUint64(params.btcAmount),
            estimatedMonthlyPayment: SafeCast.toUint96(monthlyPayment),
            amountRepaidInCurrentPeriod: 0,
            insuranceID: params.insuranceID
        });

        // Update user loan indexing for multi-loan support
        uint256 loanIndex = $.userLoanCount[params.user];
        $.userLoanAtIndex[params.user][loanIndex] = lsa;
        unchecked {
            $.userLoanCount[params.user] = loanIndex + 1;
        }

        _executeTransfersAndFlashLoan(ctx, params, lsa, loanAmount);
    }

    /**
     * @notice Handles fund transfers, flash loan execution, and surplus refund
     * @dev Extracted from `executeInitializeLoan` to reduce stack depth for coverage builds.
     * Transfers the user's deposit and premium, initiates the Aave V3 flash loan,
     * and refunds any USDC surplus from the exactOut swap.
     * @param ctx Context containing protocol addresses and configuration
     * @param params Parameters for loan initialization
     * @param lsa The Loan Specific Address created for this loan
     * @param loanAmount The calculated loan amount to flash-borrow
     */
    function _executeTransfersAndFlashLoan(
        DataTypes.InitializeLoanContext memory ctx,
        DataTypes.ExecuteInitializeLoanParams memory params,
        address lsa,
        uint256 loanAmount
    ) private {
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
        bytes memory flData = abi.encode(lsa, params.btcAmount);
        bytes memory paramsForFL = abi.encode(initializingLoan, flData);

        ctx.aavePool.executeFlashLoan(address(this), ctx.debtAsset, loanAmount, paramsForFL);

        /// @dev Refund any USDC surplus from the exactOut swap to the user.
        /// The swap consumes at most `deposit + loanAmount` but typically less,
        /// leaving a surplus that belongs to the depositing user.
        uint256 surplus = IERC20(ctx.debtAsset).balanceOf(address(this)) - balBefore;
        if (surplus > 0) IERC20(ctx.debtAsset).safeTransfer(params.user, surplus);
    }

    /**
     * @notice Updates the insurance ID for a specific loan
     * @dev Called after insurance is confirmed for a loan.
     * Loan data invariants:
     * - MUST only be updatable by the Loan contract (via EXECUTOR role) (Invariant 1.4)
     * - Access control is enforced at the Loan.sol caller level via `restricted` modifier
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param lsa The Loan Specific Address
     * @param insuranceID The new insurance ID to set
     */
    function updateInsuranceId(bytes32 storageSlot, address lsa, uint256 insuranceID) public {
        _resolveStorage(storageSlot).loansByLSA[lsa].insuranceID = insuranceID;
    }

    /**
     * @notice Updates loan data after a micro-liquidation event
     * @dev Reduces duration by 1 month and updates payment timestamp.
     * Micro-liquidation occurs when a monthly payment is missed and the protocol
     * liquidates one month's worth of collateral.
     *
     * Loan data invariants:
     * - MUST only be updatable by the Loan contract or LendingPoolCollateralManager (Invariant 1.4)
     *
     * Micro-liquidation state update invariants (Invariant 4.8):
     * - USDC debt MUST decrease by `debtToCover` (= `estimatedMonthlyPayment`) in the lending pool
     * - `duration` MUST decrease by exactly 1 month
     * - `status` MUST remain Active (not Liquidated)
     * - `lastPaymentTimestamp` MUST be set to `block.timestamp`
     *
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param lsa The Loan Specific Address being liquidated
     * @return newDuration The remaining loan duration after deduction
     */
    function updateLoanDataForMicroLiquidation(bytes32 storageSlot, address lsa) public returns (uint256 newDuration) {
        DataTypes.LoanData storage loan = _resolveStorage(storageSlot).loansByLSA[lsa];

        newDuration = uint256(loan.duration).zeroFloorSub(1);

        loan.duration = SafeCast.toUint16(newDuration);
        loan.lastPaymentTimestamp = SafeCast.toUint32(block.timestamp);
    }

    /**
     * @notice Completes the loan after the final micro-liquidation when `duration == 1`
     * @dev Sets `duration` to 0, updates `lastPaymentTimestamp`, and marks `status` as `Completed`.
     * Called by the lending pool when the last remaining period is micro-liquidated,
     * after which remaining collateral is returned to the borrower.
     *
     * Loan data invariants:
     * - MUST only be updatable by the Loan contract or LendingPoolCollateralManager (Invariant 1.4)
     *
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param lsa The Loan Specific Address being completed
     */
    function updateLoanForMicroLiquidationCompletion(bytes32 storageSlot, address lsa) public {
        DataTypes.LoanData storage loan = _resolveStorage(storageSlot).loansByLSA[lsa];

        loan.duration = 0;
        loan.lastPaymentTimestamp = SafeCast.toUint32(block.timestamp);
        loan.status = DataTypes.LoanStatus.Completed;
    }

    /**
     * @notice Updates loan data after a full liquidation event
     * @dev Sets duration to 0 and status to Liquidated.
     * Full liquidation occurs when collateral value drops below debt threshold.
     *
     * Loan data invariants:
     * - MUST only be updatable by the Loan contract or LendingPoolCollateralManager (Invariant 1.4)
     *
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param lsa The Loan Specific Address being liquidated
     */
    function updateLoanDataForFullLiquidation(bytes32 storageSlot, address lsa) public {
        DataTypes.LoanData storage loan = _resolveStorage(storageSlot).loansByLSA[lsa];

        loan.duration = 0;
        loan.lastPaymentTimestamp = SafeCast.toUint32(block.timestamp);
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
        uint256 btcPriceUSD = oracle.getAssetPrice(data.btc);
        uint256 debtPriceUSD = oracle.getAssetPrice(data.debtAsset);

        if (btcPriceUSD == 0 || debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        // Fetch max variable borrow rate from interest rate strategy
        DataTypes.ReserveData memory reserveData = ILendingPool(data.bitmorPool).getReserveData(data.debtAsset);

        uint256 maxInterestRate =
            IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress).getMaxVariableBorrowRate();

        // Fetch flash loan premium from Aave V3
        uint256 flashLoanPremiumBps = data.aavePool.getFlashLoanPremium();

        // Calculate loan amount and monthly payment using fetched rate
        (exactLoanAmt, monthlyPayAmt, minDepositRequired) = LoanMath.calculateLoanAmt(
            DataTypes.CalculateLoanAmt(
                data.depositAmount,
                data.debtAssetDecimals,
                data.btcAmount,
                data.btcAssetDecimals,
                btcPriceUSD,
                debtPriceUSD,
                maxInterestRate,
                data.duration,
                data.minDepositBps,
                flashLoanPremiumBps
            )
        );
    }

    /**
     * @notice Calculates loan details for a given collateral amount and duration
     * @dev Used by `Loan.getLoanDetails()` to preview loan terms before creation.
     * Fetches current oracle prices and interest rates to compute values.
     * @param ctx Context containing collateral bounds, deposit BPS, and protocol addresses
     * @param btcAmount Amount of collateral (8 decimals for cbBTC)
     * @param duration Loan duration in months
     * @return exactLoanAmt The loan amount in debt asset (6 decimals for USDC)
     * @return monthlyPayAmt The estimated monthly payment (6 decimals)
     * @return minDepositRequired The minimum deposit required (6 decimals)
     */
    function calculateLoanDetails(DataTypes.CalculateLoanDetailsContext memory ctx, uint256 btcAmount, uint256 duration)
        public
        view
        returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        if (btcAmount < ctx.minBTCAmt) revert Errors.LessThanMinBTCAllowed();
        if (btcAmount > ctx.maxBTCAmt) revert Errors.GreaterThanMaxBTCAllowed();
        if (duration == 0 || duration > ctx.maxDuration) revert Errors.Loan__InvalidDuration();

        return _fetchPricesAndCalculate(ctx, btcAmount, duration);
    }

    /// @dev Extracted to a separate function to avoid stack-too-deep in calculateLoanDetails
    function _fetchPricesAndCalculate(
        DataTypes.CalculateLoanDetailsContext memory ctx,
        uint256 btcAmount,
        uint256 duration
    ) private view returns (uint256, uint256, uint256) {
        DataTypes.CalculateLoanAmt memory p;
        p.btcAmount = btcAmount;
        p.duration = duration;
        p.minDepositBps = ctx.minDepositBps;

        {
            IPriceOracleGetter oracle = IPriceOracleGetter(ctx.oracle);
            p.btcPriceUSD = oracle.getAssetPrice(ctx.btc);
            p.debtPriceUSD = oracle.getAssetPrice(ctx.debtAsset);
            p.btcAssetDecimals = IERC20Metadata(ctx.btc).decimals();
            p.debtAssetDecimals = IERC20Metadata(ctx.debtAsset).decimals();
        }

        if (p.btcPriceUSD == 0 || p.debtPriceUSD == 0) revert Errors.InvalidAssetPrice();

        {
            DataTypes.ReserveData memory reserveData = ILendingPool(ctx.bitmorPool).getReserveData(ctx.debtAsset);
            p.interestRate =
                IReserveInterestRateStrategy(reserveData.interestRateStrategyAddress).getMaxVariableBorrowRate();
        }

        p.flashLoanPremiumBps = ctx.aavePool.getFlashLoanPremium();

        return LoanMath.calculateLoanDetails(p);
    }

    /**
     * @notice Validates ownership, repays dust debt from borrower if needed, and claims remaining collateral
     * @dev Called via DELEGATECALL — `msg.sender` reflects the original caller (borrower).
     * @param lsa The Loan Specific Address with surplus collateral
     * @param borrower Cached borrower address (caller must validate ownership before calling)
     * @param status Current loan status (caller must read from storage before calling)
     * @param bitmorPool Bitmor Lending Pool address
     * @param debtAsset Debt asset address (USDC)
     * @param collateralAsset Collateral asset address (bvBTC)
     * @param slippage_sharesToAsset Acceptable slippage in basis points for shares-to-asset conversion
     * @return assetsClaimed The amount of cbBTC assets claimed by the borrower
     */
    function executeClaimRemainingCollateral(
        address lsa,
        address borrower,
        DataTypes.LoanStatus status,
        address bitmorPool,
        address debtAsset,
        address collateralAsset,
        uint256 slippage_sharesToAsset
    ) public returns (uint256 assetsClaimed) {
        if (status == DataTypes.LoanStatus.Active) {
            revert Errors.Loan__InvalidLoanStatus();
        }
        if (msg.sender != borrower) {
            revert Errors.Loan__OnlyBorrower();
        }

        // Repay dust debt from borrower if Aave V2 rounding left residual
        uint256 dustDebt = bitmorPool.getVDTTokenAmount(debtAsset, lsa);
        if (dustDebt > 0 && dustDebt <= Constants.DEBT_DUST_THRESHOLD) {
            IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), dustDebt);
            bitmorPool.repayDustDebt(debtAsset, lsa, dustDebt);
            emit ILoan.Loan__DustDebtAbsorbed(lsa, dustDebt);
        }

        assetsClaimed = lsa.claimSurplusCollateral({
            bitmorPool: bitmorPool,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            borrower: borrower,
            slippage_sharesToAsset: slippage_sharesToAsset
        });
    }
}
