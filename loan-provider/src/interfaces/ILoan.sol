// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {DataTypes} from "../libraries/types/DataTypes.sol";

/**
 * @title ILoan
 * @author Bitmor Protocol
 * @notice Interface for the main Bitmor Protocol loan contract
 * @dev Defines all external functions for loan creation, management, and queries
 */
interface ILoan {
    // ============ Events ============

    /**
     * @notice Emitted when a new loan is created
     * @param borrower Address of the loan borrower
     * @param lsa Address of the created Loan Specific Address
     * @param loanAmount Total loan amount in USDC (6 decimals)
     * @param collateralAmount Amount of cbBTC collateral (8 decimals)
     * @param data Additional data for insurance management
     */
    event Loan__LoanCreated(
        address indexed borrower, address indexed lsa, uint256 loanAmount, uint256 collateralAmount, bytes data
    );

    /**
     * @notice Emitted when a loan's status changes
     * @param lsa Address of the Loan Specific Address
     * @param oldStatus Previous loan status
     * @param newStatus New loan status
     */
    event Loan__LoanStatusUpdated(
        address indexed lsa, DataTypes.LoanStatus indexed oldStatus, DataTypes.LoanStatus indexed newStatus
    );

    /**
     * @notice Emitted when the maximum loan amount is updated
     * @param newAmount New maximum loan amount
     */
    event Loan__MaxLoanAmountUpdated(uint256 indexed newAmount);

    /**
     * @notice Emitted when a loan is closed via early pre-closure
     * @param lsa Address of the closed Loan Specific Address
     */
    event Loan__ClosedLoan(address indexed lsa);

    /**
     * @notice Emitted when a loan is completed.
     * @param lsa Address of the completed Loan Specific Address
     */
    event Loan__Completed(address indexed lsa);

    /// @notice Emitted when a loan is completed with negligible dust debt remaining
    /// @dev Dust debt arises from Aave V2 rayMul/rayDiv rounding during repayment.
    ///      Amount is bounded by `Constants.DEBT_DUST_THRESHOLD` (10 wei).
    /// @param lsa Address of the Loan Specific Address
    /// @param dustAmount Amount of residual debt in wei
    event Loan__DustDebtAbsorbed(address indexed lsa, uint256 dustAmount);

    /**
     * @notice Emitted when the LoanVaultFactory address is updated
     * @param newFactory Address of the new factory contract
     */
    event Loan__LoanVaultFactoryUpdated(address indexed newFactory);

    /**
     * @notice Emitted when the escrow address is updated
     * @param newEscrow Address of the new escrow contract
     */
    event Loan__EscrowUpdated(address indexed newEscrow);

    /**
     * @notice Emitted when the swapper address is updated
     * @param newSwapper Address of the new swapper contract
     */
    event Loan__SwapperUpdated(address indexed newSwapper);

    /**
     * @notice Emitted when a loan repayment is made
     * @param lsa Address of the Loan Specific Address
     * @param amountRepaid Amount of USDC repaid (6 decimals)
     */
    event Loan__LoanRepaid(address indexed lsa, uint256 indexed amountRepaid);

    /**
     * @notice Emitted when loan data is updated after a micro liquidation
     * @param lsa Address of the Loan Specific Address
     * @param newDuration Remaining loan duration in months after reduction
     */
    event Loan__LoanDataForMicroLiquidationUpdated(address indexed lsa, uint256 indexed newDuration);

    /**
     * @notice Emitted when loan data is updated after a full liquidation
     * @param lsa Address of the Loan Specific Address
     */
    event Loan__LoanDataForFullLiquidationUpdated(address indexed lsa);

    /**
     * @notice Emitted when the insurance ID for a loan is updated
     * @param lsa Address of the Loan Specific Address
     * @param insuranceID New insurance ID assigned to the loan
     */
    event Loan__InsuranceIDUpdated(address indexed lsa, uint256 indexed insuranceID);

    /**
     * @notice Emitted when the premium collector address is updated
     * @param newPremiumCollector Address of the new premium collector
     */
    event Loan__PremiumCollectorUpdated(address indexed newPremiumCollector);

    /**
     * @notice Emitted when the grace period is updated
     * @param newGracePeriod New grace period value in seconds
     */
    event Loan__GracePeriodUpdated(uint256 indexed newGracePeriod);

    /**
     * @notice Emitted when the pre-closure fee is updated
     * @param newPreClosureFee New pre-closure fee in basis points
     */
    event Loan__PreClosureFeeUpdated(uint256 indexed newPreClosureFee);

    /**
     * @notice Emitted when the shares-to-asset slippage tolerance is updated
     * @param newSlippage New slippage value in basis points
     */
    event Loan__SlippageForSharesToAssetUpdated(uint256 indexed newSlippage);

    /**
     * @notice Emitted when the swap slippage tolerance is updated
     * @param newSlippage New slippage value in basis points
     */
    event Loan__SlippageForSwapUpdated(uint256 indexed newSlippage);

    /**
     * @notice Emitted when the maximum BTC collateral amount is updated
     * @param newMaxBTCAmount New maximum BTC amount (8 decimals)
     */
    event Loan__MaxBTCAmountUpdated(uint256 indexed newMaxBTCAmount);

    /**
     * @notice Emitted when the minimum BTC collateral amount is updated
     * @param newMinBTCAmount New minimum BTC amount (8 decimals)
     */
    event Loan__MinBTCAmountUpdated(uint256 indexed newMinBTCAmount);

    /**
     * @notice Emitted when the minimum deposit percentage is updated
     * @param newMinDepositBps New minimum deposit in basis points
     */
    event Loan__MinDepositUpdated(uint256 indexed newMinDepositBps);

    /**
     * @notice Emitted when the liquidation fee is updated
     * @param newLiquidationFee New liquidation fee in basis points
     */
    event Loan__LiquidationFeeUpdated(uint256 indexed newLiquidationFee);

    /**
     * @notice Emitted when the liquidation fee collector address is updated
     * @param newLiquidationFeeCollector Address of the new liquidation fee collector
     */
    event Loan__LiquidationFeeCollectorUpdated(address indexed newLiquidationFeeCollector);

    /**
     * @notice Emitted when the maximum loan duration is updated
     * @param newMaxDuration New maximum duration in months
     */
    event Loan__MaxDurationUpdated(uint256 indexed newMaxDuration);

    /// @notice Emitted when the maximum oracle staleness threshold is updated
    /// @param newMaxStaleness New maximum staleness in seconds
    event Loan__MaxOracleStalenessUpdated(uint256 indexed newMaxStaleness);

    /**
     * @notice Emitted when a borrower successfully claims surplus collateral after liquidation or completion
     * @param lsa Address of the Loan Specific Address
     * @param borrower Address of the borrower who received the collateral
     * @param assetsClaimed Amount of assets claimed by the borrower
     */
    event Loan__SurplusCollateralClaimed(address indexed lsa, address indexed borrower, uint256 assetsClaimed);

    // ============ Main Functions ============

    /**
     * @notice Initializes a new loan with `depositAmount` USDC deposit
     * @dev Creates LSA, calculates loan terms, stores loan data on-chain, and executes flash loan flow
     * @param depositAmount USDC deposit amount (6 decimals)
     * @param premiumAmount USDC premium amount (6 decimals)
     * @param collateralAmount Target cbBTC amount user wants to achieve (8 decimals)
     * @param duration Loan duration in months
     * @param data Data for insurance management
     * @return lsa Address of the created Loan Specific Address
     * @custom:access Restricted to `EXECUTOR` role
     */
    function initializeLoan(
        uint256 depositAmount,
        uint256 premiumAmount,
        uint256 collateralAmount,
        uint256 duration,
        bytes calldata data
    ) external returns (address lsa);

    /**
     * @notice Updates the `insuranceID` for a given `lsa`
     * @param lsa The LSA address
     * @param insuranceID New insurance ID for the `lsa`
     * @custom:access Restricted to `EXECUTOR` role
     */
    function updateInsuranceId(address lsa, uint256 insuranceID) external;

    /**
     * @notice Updates the LoanData for a specific `_lsa` in case of micro liquidation
     * @dev Reduces the loan `duration` by 1 and updates `lastPaymentTimestamp` to `block.timestamp`.
     * @param _lsa The Loan Specific Address
     * @custom:access Restricted to `LPCM` role
     */
    function updateLoanDataForMicroLiquidation(address _lsa) external;

    /**
     * @notice Completes a micro-liquidation for `_lsa` when `duration == 1`
     * @dev Sets `duration` to 0, `status` to `LoanStatus.Completed`, and updates `lastPaymentTimestamp`.
     *      Surplus collateral (if any) must be claimed separately by the borrower via `claimSurplusCollateral`.
     * @param _lsa The Loan Specific Address
     * @custom:access Restricted to `LPCM` role
     */
    function updateLoanForMicroLiquidationCompletion(address _lsa) external;

    /**
     * @notice Updates the LoanData for a specific `_lsa` in case of full liquidation
     * @dev Sets `duration` to 0, `status` to `LoanStatus.Liquidated`, and updates `lastPaymentTimestamp`.
     *      Surplus collateral (if any) must be claimed separately by the borrower via `claimSurplusCollateral`.
     * @param _lsa The Loan Specific Address
     * @custom:access Restricted to `LPCM` role
     */
    function updateLoanDataForFullLiquidation(address _lsa) external;

    // ============ View Functions ============

    /**
     * @notice Retrieves loan data for a specific LSA
     * @param lsa The LSA address
     * @return Loan data struct containing all loan information
     */
    function getLoanByLSA(address lsa) external view returns (DataTypes.LoanData memory);

    /**
     * @notice Gets total number of loans created by `user`
     * @param user The user address
     * @return Total loan count
     */
    function getUserLoanCount(address user) external view returns (uint256);

    /**
     * @notice Gets LSA address for user's Nth loan
     * @param user The user address
     * @param index Loan index (0-based)
     * @return LSA address
     */
    function getUserLoanAtIndex(address user, uint256 index) external view returns (address);

    /**
     * @notice Retrieves all loans for a specific `user`
     * @param user The user address
     * @return Array of loan data structs
     */
    function getUserAllLoans(address user) external view returns (DataTypes.LoanData[] memory);

    /**
     * @notice Gets the collateral asset address
     * @return cbBTC address
     */
    function getCollateralAsset() external view returns (address);

    /**
     * @notice Gets the debt asset address
     * @return USDC address
     */
    function getDebtAsset() external view returns (address);

    /**
     * @notice Calculates strike price for options based on `loanAmount` and `deposit`
     * @dev Formula: strike_price = btc_in_usd * loanAmount/(loanAmount + deposit) * 1.1
     * @param loanAmount The loan amount in USDC (6 decimals)
     * @param deposit The deposit amount in USDC (6 decimals)
     * @return strikePrice Strike price in USD (8 decimals)
     */
    function calculateStrikePrice(uint256 loanAmount, uint256 deposit) external view returns (uint256 strikePrice);

    // ============ User Actions ============

    /**
     * @notice Allows borrower to repay their loan with `amount` USDC
     * @dev Repays debt on Aave V2 and updates loan state (loanAmount, lastPaymentTimestamp, nextDueTimestamp)
     * @param lsa The Loan Specific Address
     * @param amount Amount of USDC to repay (6 decimals)
     * @return finalAmountRepaid The actual amount repaid
     */
    function repay(address lsa, uint256 amount) external returns (uint256 finalAmountRepaid);

    /**
     * @notice Close the debt position of the `lsa` using flash loan and send the collateral asset or debt asset (as requested)
     * @dev Withdraws from escrow where excess collateral is locked
     * @param lsa The Loan Specific Address
     * @param withdrawInBTC If true, the collateral asset will be transfered to the `loan.borrower` else collateral value worth of debt asset will be transferred.
     */
    function closeLoan(address lsa, bool withdrawInBTC) external;

    /**
     * @notice Allows the borrower to claim surplus collateral after liquidation or micro-liquidation completion
     * @dev Only callable by the loan's borrower when loan is no longer Active (i.e., Liquidated or Completed).
     *      Withdraws aToken collateral from the Bitmor Lending Pool, redeems bvBTC shares, and transfers
     *      the underlying cbBTC to the borrower. Reverts if outstanding debt exists or no collateral remains.
     * @param _lsa The Loan Specific Address with surplus collateral
     * @return assetsClaimed The amount of assets claimed by the borrower
     */
    function claimSurplusCollateral(address _lsa) external returns (uint256 assetsClaimed);

    // ============ Admin Functions ============

    /**
     * @notice Updates the loan vault factory address
     * @param newFactory New factory address
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setLoanVaultFactory(address newFactory) external;

    /**
     * @notice Updates the swapper contract address
     * @param newSwapper New swapper address
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setSwapper(address newSwapper) external;

    /**
     * @notice Updates the premium collector address
     * @param newPremiumCollector New premium collector address
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setPremiumCollector(address newPremiumCollector) external;

    /// @notice Returns the `s_premiumCollector` address.
    /// @return premiumCollector The premium collector address
    function getPremiumCollector() external view returns (address premiumCollector);

    /**
     * @notice Updates the grace period for monthly payment overdue checks
     * @dev Reverts with `InvalidInputs` if `gracePeriod` > `MAX_GRACE_PERIOD` (45 days)
     * @param gracePeriod New grace period in seconds
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setGracePeriod(uint256 gracePeriod) external;

    /// @notice Returns the `s_gracePeriod` value in seconds.
    /// @return gracePeriod The current grace period in seconds
    function getGracePeriod() external view returns (uint256 gracePeriod);

    /// @notice Returns the `LOAN_REPAYMENT_INTERVAL` constant (30 days in seconds).
    /// @return The repayment interval in seconds
    function getRepaymentInterval() external view returns (uint256);

    /// @notice Returns the loan pre-closure fee in basis points.
    /// @return The pre-closure fee in basis points
    function getPreClosureFee() external view returns (uint256);

    /**
     * @notice Updates the pre-closure fee
     * @dev Reverts with `InvalidFee` if `newFee` >= `BASIS_POINT_SCALE` (10000 bps)
     * @param newFee New pre-closure fee in basis points
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setPreClosureFee(uint256 newFee) external;

    /**
     * @notice Calculates loan details based on `collateralAmount` and `duration`
     * @param collateralAmount Collateral asset amount in cbBTC (8 decimals)
     * @param duration Duration of the loan in months
     * @return loanAmount Debt asset amount in USDC (6 decimals)
     * @return monthlyPayment Estimated monthly payment amount in USDC (6 decimals)
     * @return minDepositRequired Minimum deposit required in USDC to initialize loan (6 decimals)
     */
    function getLoanDetails(uint256 collateralAmount, uint256 duration)
        external
        view
        returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired);

    /**
     * @notice Updates the slippage tolerance for `bvBTC` shares-to-asset conversion
     * @dev Reverts with `InvalidSlippage` if `newSlippage` >= `BASIS_POINT_SCALE` (10000 bps)
     * @param newSlippage New slippage value in basis points
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setSlippageForSharesToAsset(uint256 newSlippage) external;

    /// @notice Returns the `s_slippage_sharesToAsset` value in basis points.
    /// @return The current shares-to-asset slippage tolerance in basis points
    function getSlippageForSharesToAsset() external view returns (uint256);

    /**
     * @notice Updates the slippage tolerance for token swaps
     * @dev Reverts with `InvalidSlippage` if `newSlippage` >= `BASIS_POINT_SCALE` (10000 bps)
     * @param newSlippage New slippage value in basis points
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setSlippageForSwap(uint256 newSlippage) external;

    /// @notice Returns the `s_slippage_swap` value in basis points.
    /// @return The current swap slippage tolerance in basis points
    function getSlippageForSwap() external view returns (uint256);

    /**
     * @notice Updates the maximum BTC collateral amount
     * @dev Reverts if `newMaxBTCAmt` is less than the current minimum
     * @param newMaxBTCAmt New maximum BTC amount (8 decimals)
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setMaxBTCAmount(uint256 newMaxBTCAmt) external;

    /// @notice Returns the `s_maxBTCAmt` value (8 decimals).
    /// @return The maximum BTC collateral amount
    function getMaxBTCAmount() external view returns (uint256);

    /**
     * @notice Updates the minimum BTC collateral amount
     * @param newMinBTCAmt New minimum BTC amount (8 decimals)
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setMinBTCAmount(uint256 newMinBTCAmt) external;

    /// @notice Returns the `s_minBTCAmt` value (8 decimals).
    /// @return The minimum BTC collateral amount
    function getMinBTCAmount() external view returns (uint256);

    /// @notice Returns the `s_minDeposit` value in basis points.
    /// @return The minimum deposit percentage in basis points
    function getMinDepositBps() external view returns (uint256);

    /**
     * @notice Updates the minimum deposit percentage
     * @dev Reverts with `InvalidInputs` if `newMinDepositBps` >= `BASIS_POINT_SCALE` (10000 bps)
     * @param newMinDepositBps New minimum deposit in basis points
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setMinDepositBps(uint256 newMinDepositBps) external;

    /**
     * @notice Updates the liquidation fee applied to the liquidation bonus
     * @dev Reverts if `newLiquidationFee` exceeds `MAX_LIQUIDATION_FEE` (20%)
     * @param newLiquidationFee New liquidation fee in basis points
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setLiquidationFeeBps(uint256 newLiquidationFee) external;

    /// @notice Returns the `s_liquidationFee` value in basis points.
    /// @return The current liquidation fee in basis points
    function getLiquidationFeeBps() external view returns (uint256);

    /// @notice Returns the `s_liquidationFeeCollector` address.
    /// @return The address that receives liquidation fees
    function getLiquidationFeeCollector() external view returns (address);

    /**
     * @notice Updates the maximum allowed loan duration
     * @dev Reverts if `newMaxDuration` is zero
     * @param newMaxDuration New maximum duration in months
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setMaxDuration(uint256 newMaxDuration) external;

    /// @notice Returns the `s_maxDuration` value in months.
    /// @return The maximum loan duration in months
    function getMaxDuration() external view returns (uint256);

    /// @notice Updates the maximum allowed oracle staleness for BTC price feeds
    /// @param newMaxStaleness New maximum staleness in seconds (e.g., 3600 = 1 hour)
    /// @custom:access Restricted to `LPM_SLOW` role
    function setMaxOracleStaleness(uint256 newMaxStaleness) external;

    /// @notice Returns the maximum allowed oracle staleness in seconds
    /// @return The current max oracle staleness threshold
    function getMaxOracleStaleness() external view returns (uint256);

    /**
     * @notice Updates the liquidation fee collector address
     * @param newFeeCollector New liquidation fee collector address
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function setLiquidationFeeCollector(address newFeeCollector) external;
}
