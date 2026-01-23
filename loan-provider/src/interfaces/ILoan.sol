// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {DataTypes} from "../libraries/types/DataTypes.sol";

/**
 * @title ILoan
 * @notice Interface for the main Bitmor Protocol loan contract
 * @dev Defines all external functions for loan creation, management, and queries
 */
interface ILoan {
    // ============ Events ============

    event Loan__LoanCreated(
        address indexed borrower, address indexed lsa, uint256 loanAmount, uint256 collateralAmount, bytes data
    );

    event Loan__LoanStatusUpdated(
        address indexed lsa, DataTypes.LoanStatus indexed oldStatus, DataTypes.LoanStatus indexed newStatus
    );

    event Loan__MaxLoanAmountUpdated(uint256 indexed newAmount);

    event Loan__ClosedLoan(address indexed lsa);

    event Loan__LoanVaultFactoryUpdated(address indexed newFactory);

    event Loan__EscrowUpdated(address indexed newEscrow);

    event Loan__SwapAdapterUpdated(address indexed newSwapAdapter);

    event Loan__ZQuoterUpdated(address indexed newZQuoter);

    event Loan__LoanRepaid(address indexed lsa, uint256 indexed amountRepaid);

    event Loan__LoanDataForMicroLiquidationUpdated(address indexed lsa, uint256 indexed newDuration);

    event Loan__LoanDataForFullLiquidationUpdated(address indexed lsa);

    event Loan__InsuranceIDUpdated(address indexed lsa, uint256 indexed insuranceID);

    event Loan__PremiumCollectorUpdated(address indexed newPremiumCollector);

    event Loan__GracePeriodUpdated(uint256 indexed newGracePeriod);

    event Loan__PreClosureFeeUpdated(uint256 indexed newPreClosureFee);

    event Loan__LiquidationBufferUpdated(uint256 indexed newBuffer);

    event Loan__SlippageForSharesToAssetUpdated(uint256 indexed newSlippage);

    event Loan__SlippageForSwapUpdated(uint256 indexed newSlippage);

    event Loan__MaxBTCAmountUpdated(uint256 newMaxBTCAmount);

    event Loan__MinBTCAmountUpdated(uint256 newMinBTCAmount);

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
     */
    function initializeLoan(
        uint256 depositAmount,
        uint256 premiumAmount,
        uint256 collateralAmount,
        uint256 duration,
        bytes calldata data
    ) external returns (address lsa);

    /**
     * @notice Updates `lsa` `insuranceID`
     * @dev Restricted to use ONLY BY `EXECUTOR` ROLE.
     * @param lsa The LSA address
     * @param insuranceID Insurance Id for the `lsa`
     */
    function updateInsuranceId(address lsa, uint256 insuranceID) external;

    /**
     * @notice Updates the LoanData for a specific `lsa` in case of it's microliquidtion.
     * @dev Reduce the loan `duration` by 1 and updates the `lastPaymentTimestamp` with `block.timestamp`.
     * @dev This call is restricted to `LPCM` role ONLY.
     * @param _lsa The Loan Specific Address
     */
    function updateLoanDataForMicroLiquidation(address _lsa) external;

    /**
     * @notice Updates the LoanData for a specific `lsa` in case of it's microliquidtion.
     * @dev Updates the loan `duration` with 0, `status` with `LoanStatus.Liquidated` and the `lastPaymentTimestamp` with `block.timestamp`.
     * @dev This call is restricted to `LPCM` role ONLY.
     * @param _lsa The Loan Specific Address
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
     * @param withdrawInCollateralAsset If true, the collateral asset will be transfered to the `loan.borrower` else collateral value worth of debt asset will be transferred.
     */
    function closeLoan(address lsa, bool withdrawInCollateralAsset) external;

    // ============ Admin Functions ============

    /**
     * @notice Updates the loan vault factory address
     * @param newFactory New factory address
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setLoanVaultFactory(address newFactory) external;

    /**
     * @notice Updates the swap adapter contract address
     * @param newSwapAdapter New swap adapter address
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setSwapAdapter(address newSwapAdapter) external;

    /**
     * @notice Updates the zQuoter contract address
     * @param newZQuoter New zQuoter address
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setZQuoter(address newZQuoter) external;

    /**
     * @notice Updates the premium collector address
     * @param newPremiumCollector New premium collector address
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setPremiumCollector(address newPremiumCollector) external;

    /**
     * @notice Get the premium collector address
     */
    function getPremiumCollector() external view returns (address premiumCollector);

    /**
     * @notice Updates the grace period for microLiquidation.
     * @param gracePeriod New grace period in `days`
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setGracePeriod(uint256 gracePeriod) external;

    /**
     * @notice Returns the `s_gracePeriod`.
     */
    function getGracePeriod() external view returns (uint256 gracePeriod);

    /**
     * @notice Returns `LOAN_REPAYMENT_INTERVAL` constant value.
     */
    function getRepaymentInterval() external view returns (uint256);

    /**
     * @notice Returns the loan pre-closure fee (in bps)
     */
    function getPreClosureFee() external view returns (uint256);

    /**
     * @notice Updates the pre-closure fee (in bps)
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setPreClosureFee(uint256 newFee) external;

    /**
     * @notice Updates the buffer required while Liquidation.
     * @param newBuffer The new buffer (in bps)
     * @dev This call is restricted to `LPM_SLOW` ONLY.
     */
    function setLiquidationBuffer(uint256 newBuffer) external;

    /**
     * @notice Returns the buffer required while liquidation.
     */
    function getLiquidationBuffer() external view returns (uint256);

    /**
     * @notice Getter function to calculate the loan details based on the `collateralAmount` and `duration` of the Loan.
     * @param collateralAmount Collateral asset amount
     * @param duration Duration of the loan
     * @return loanAmount Debt asset amount
     * @return monthlyPayment estimated monthly payment amount in debt asset
     * @return minDepositRequired Minimum deposit required in debt asset to initialize loan
     */
    function getLoanDetails(uint256 collateralAmount, uint256 duration)
        external
        view
        returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired);

    function setSlippageForSharesToAsset(uint256 newSlippage) external;

    function getSlippageForSharesToAsset() external view returns (uint256);

    function setSlippageForSwap(uint256 newSlippage) external;

    function getSlippageForSwap() external view returns (uint256);

    function setMaxBTCAmount(uint256 newMaxBTCAmt) external;

    function getMaxBTCAmount() external view returns (uint256);

    function setMinBTCAmount(uint256 newMinBTCAmt) external;

    function getMinBTCAmount() external view returns (uint256);
}
