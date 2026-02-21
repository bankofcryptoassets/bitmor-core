// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title DataTypes
 * @author Bitmor Protocol
 * @notice Library containing all data structures used across the Bitmor Protocol
 * @dev Centralizes struct definitions for consistency and maintainability.
 *
 * ## Structure Categories
 *
 * ### Aave V2 Compatibility
 * - `ReserveData`: Reserve configuration from Bitmor Lending Pool
 * - `ReserveConfigurationMap`: Bit-packed reserve configuration
 * - `UserConfigurationMap`: User's reserve configuration
 *
 * ### Loan Management
 * - `LoanData`: Complete loan information stored per LSA
 * - `LoanStatus`: Enum for loan lifecycle states
 * - Various execution parameter structs for loan operations
 *
 * ### BTC Vault
 * - `Strategy`: Tokenized strategy configuration
 * - `StrategyState`: Complete strategy management state
 * - `VaultState`: Vault fee configuration
 * - `Allocation`: Reallocation instruction struct
 */
library DataTypes {
    /*
       _    _ _   _______     ______   ____  _____ ______ ______      ________
      | |  | | |  |  ____|   |  ____| |  _ \|  __ \  ____|  ____|    /  ____  \
      | |__| | |  | |__      | |__    | |_| | |__) | |__  | |__     |  /    \  |
      |  __  | |  |  __|     |  __|   |  _ <|  _  /|  __| |  __|    | |      | |
      | |  | | |__| |____    | |      | |_| | | \ \| |____| |____   |  \____/  |
      |_|  |_|____|______|   |_|      |____/|_|  \_\______|______|   \________/
    */

    /**
     * @notice Reserve data structure from Aave V2 (Bitmor Lending Pool)
     * @dev Refer to the Aave whitepaper, section 1.1 for formal description
     */
    struct ReserveData {
        /**
         * @dev Stores the reserve configuration (bit-packed)
         */
        ReserveConfigurationMap configuration;
        /**
         * @dev The liquidity index, expressed in RAY (27 decimals)
         */
        uint128 liquidityIndex;
        /**
         * @dev Variable borrow index, expressed in RAY
         */
        uint128 variableBorrowIndex;
        /**
         * @dev The current supply rate, expressed in RAY
         */
        uint128 currentLiquidityRate;
        /**
         * @dev The current variable borrow rate, expressed in RAY
         */
        uint128 currentVariableBorrowRate;
        /**
         * @dev The current stable borrow rate, expressed in RAY
         */
        uint128 currentStableBorrowRate;
        /**
         * @dev Timestamp of the last reserve update
         */
        uint40 lastUpdateTimestamp;
        /**
         * @dev Address of the associated aToken (interest-bearing token)
         */
        address aTokenAddress;
        /**
         * @dev Address of the stable debt token
         */
        address stableDebtTokenAddress;
        /**
         * @dev Address of the variable debt token
         */
        address variableDebtTokenAddress;
        /**
         * @dev Address of the interest rate strategy contract
         */
        address interestRateStrategyAddress;
        /**
         * @dev The reserve ID (position in the active reserves list)
         */
        uint8 id;
    }

    /**
     * @notice Bit-packed reserve configuration
     * @dev Configuration is stored in a single uint256 for gas efficiency
     */
    struct ReserveConfigurationMap {
        /**
         * @dev Bit layout:
         * - bits 0-15: LTV (Loan-to-Value ratio)
         * - bits 16-31: Liquidation threshold
         * - bits 32-47: Liquidation bonus
         * - bits 48-55: Decimals
         * - bit 56: Reserve is active
         * - bit 57: Reserve is frozen
         * - bit 58: Borrowing is enabled
         * - bit 59: Stable rate borrowing enabled
         * - bits 60-63: Reserved
         * - bits 64-79: Reserve factor
         */
        uint256 data;
    }

    /**
     * @notice User-specific configuration for reserve interactions
     * @dev Bit-packed user configuration across all reserves
     */
    struct UserConfigurationMap {
        /**
         * @dev Bit-packed data indicating which reserves user is using as collateral/borrowing
         */
        uint256 data;
    }

    /**
     * @notice Interest rate mode for borrows
     */
    enum InterestRateMode {
        /**
         * @dev No interest rate mode selected
         */
        NONE,
        /**
         * @dev Stable interest rate (fixed)
         */
        STABLE,
        /**
         * @dev Variable interest rate (fluctuates with utilization)
         */
        VARIABLE
    }

    /*
       _      ____          _   _   ____        _______       _____ _______ ____  _____  _____ ______  _____
      | |    / __ \   /\   | \ | | |  _ \      / /_   _|     / ____|__   __|  _ \|  __ \/ ____|__   __|/ ____|
      | |   | |  | | /  \  |  \| | | | | |    / /  | |      | (___    | |  | |_) | |__) | |       | |  | (___
      | |   | |  | |/ /\ \ | . ` | | | | |   / /   | |       \___ \   | |  |  _ <|  _  /| |       | |   \___ \
      | |___| |__| / ____ \| |\  | | |_| |  / /   _| |_      ____) |  | |  | |_) | | \ \| |____   | |   ____) |
      |______\____/_/    \_\_| \_| |____/  /_/   |_____|    |_____/   |_|  |____/|_|  \_\\_____|  |_|  |_____/
    */

    /**
     * @notice Parameters for initializing a new loan
     * @dev Passed to `LoanLogic.executeInitializeLoan`
     */
    struct ExecuteInitializeLoanParams {
        /**
         * @dev Address of the user creating the loan
         */
        address user;
        /**
         * @dev Initial deposit amount in debt asset (USDC, 6 decimals)
         */
        uint256 depositAmount;
        /**
         * @dev Insurance premium amount in debt asset (USDC, 6 decimals)
         */
        uint256 premiumAmount;
        /**
         * @dev Target collateral amount (cbBTC, 8 decimals)
         */
        uint256 collateralAmount;
        /**
         * @dev Loan duration in months
         */
        uint256 duration;
        /**
         * @dev Insurance ID for tracking
         */
        uint256 insuranceID;
        /**
         * @dev Additional data for insurance management
         */
        bytes data;
    }

    /**
     * @notice Context containing protocol addresses for loan initialization
     * @dev Avoids stack too deep by grouping addresses into a struct
     */
    struct InitializeLoanContext {
        /**
         * @dev Bitmor Lending Pool address
         */
        address bitmorPool;
        /**
         * @dev Price oracle address
         */
        address oracle;
        /**
         * @dev Collateral asset address (cbBTC)
         */
        address collateralAsset;
        /**
         * @dev Debt asset address (USDC)
         */
        address debtAsset;
        /**
         * @dev Aave V3 pool for flash loans
         */
        address aavePool;
        /**
         * @dev Factory for creating LSAs
         */
        address loanVaultFactory;
        /**
         * @dev Address that receives premium payments
         */
        address premiumCollector;
        /**
         * @dev Minimum collateral amount allowed (0.01 BTC)
         */
        uint256 minCollateralAmt;
        /**
         * @dev Maximum collateral amount allowed (1 BTC)
         */
        uint256 maxCollateralAmt;
        /**
         * @dev Repayment interval in seconds (30 days)
         */
        uint256 loanRepaymentInterval;
        /**
         * @dev Minimum deposit requirement in basis points (e.g., 3300 = 33%)
         */
        uint256 minDepositBps;
        /**
         * @dev Maximum loan duration in months
         */
        uint256 maxDuration;
    }

    /**
     * @notice Parameters passed to flash loan callback
     * @dev Decoded from the `params` bytes in `executeOperation`
     */
    struct ExecuteFLOperationParams {
        /**
         * @dev Flash loaned asset address
         */
        address asset;
        /**
         * @dev Flash loan amount
         */
        uint256 amount;
        /**
         * @dev Flash loan premium (fee)
         */
        uint256 premium;
        /**
         * @dev Address that initiated the flash loan
         */
        address initiator;
        /**
         * @dev Encoded operation-specific parameters
         */
        bytes params;
        /**
         * @dev Acceptable slippage in basis points for shares-to-asset conversion
         */
        uint256 slippage_sharesToAsset;
    }

    /**
     * @notice Context for flash loan operation execution
     * @dev Contains all addresses and configuration needed for FL callback
     */
    struct ExecuteFLOperationContext {
        /**
         * @dev Aave V3 pool (caller validation)
         */
        address aavePool;
        /**
         * @dev Bitmor Lending Pool for collateral operations
         */
        address bitmorPool;
        /**
         * @dev Swapper for swapping tokens
         */
        address swapper;
        /**
         * @dev Debt asset address (USDC)
         */
        address debtAsset;
        /**
         * @dev Collateral asset address (bvBTC)
         */
        address collateralAsset;
        /**
         * @dev Underlying BTC token address (cbBTC)
         */
        address btc;
        /**
         * @dev Address that receives fees
         */
        address feeCollector;
        /**
         * @dev Price oracle address
         */
        address oracle;
        /**
         * @dev Maximum slippage in basis points
         */
        uint256 maxSlippage;
    }

    /**
     * @notice Parameters for loan repayment
     */
    struct ExecuteRepayParams {
        /**
         * @dev Loan Specific Address to repay
         */
        address lsa;
        /**
         * @dev Amount to repay in debt asset
         */
        uint256 amount;
        /**
         * @dev Acceptable slippage in basis points for shares-to-asset conversion
         */
        uint256 slippage_sharesToAsset;
    }

    /**
     * @notice Context for loan closure operations
     */
    struct ExecuteCloseLoanContext {
        /**
         * @dev Bitmor Lending Pool address
         */
        address bitmorPool;
        /**
         * @dev Aave V3 pool for flash loans
         */
        address aavePool;
        /**
         * @dev Price oracle address
         */
        address oracle;
        /**
         * @dev Debt asset address (USDC)
         */
        address debtAsset;
        /**
         * @dev Collateral asset address (cbBTC)
         */
        address collateralAsset;
        /**
         * @dev Underlying BTC token address (cbBTC)
         */
        address btc;
        /**
         * @dev Pre-closure fee in basis points
         */
        uint256 preClosureFeeBps;
        /**
         * @dev Maximum slippage in basis points
         */
        uint256 maxSlippage;
    }

    /**
     * @notice Parameters for loan closure
     */
    struct ExecuteCloseLoanParams {
        /**
         * @dev Loan Specific Address to close
         */
        address lsa;
        /**
         * @dev If true, withdraw remaining, after debt+fee, as btc; if false, as debt asset
         */
        bool withdrawInBTC;
    }

    /**
     * @notice Context for previewing loan details (collateral bounds and deposit requirements)
     * @dev Used by `Loan.getLoanDetails()` to pass vault configuration parameters
     */
    struct CalculateLoanDetailsContext {
        /// @dev Minimum collateral amount allowed (e.g., 0.01 BTC in 8 decimals)
        uint256 minBTCAmt;
        /// @dev Maximum collateral amount allowed (e.g., 1 BTC in 8 decimals)
        uint256 maxBTCAmt;
        /// @dev Minimum deposit requirement in basis points (e.g., 3300 = 33%)
        uint256 minDepositBps;
        /// @dev Maximum loan duration in months
        uint256 maxDuration;
    }

    /**
     * @notice Parameters for calculating loan amount with deposit
     * @dev Used internally by LoanLogic
     */
    struct CalculateLoanAmountAndMonthlyPayment {
        /**
         * @dev Bitmor Lending Pool address
         */
        address bitmorPool;
        /**
         * @dev Price oracle address
         */
        address oracle;
        /**
         * @dev Collateral asset address
         */
        address collateralAsset;
        /**
         * @dev Debt asset address
         */
        address debtAsset;
        /**
         * @dev Aave V3 pool address for fetching flash loan premium
         */
        address aavePool;
        /**
         * @dev User's deposit amount
         */
        uint256 depositAmount;
        /**
         * @dev Debt asset decimals
         */
        uint256 debtAssetDecimals;
        /**
         * @dev Target collateral amount
         */
        uint256 collateralAmount;
        /**
         * @dev Collateral asset decimals
         */
        uint256 collateralAssetDecimals;
        /**
         * @dev Loan duration in months
         */
        uint256 duration;
        /// @dev Minimum deposit requirement in basis points (e.g., 3300 = 33%)
        uint256 minDepositBps;
    }

    /**
     * @notice Parameters for pure loan amount calculations
     * @dev Used by LoanMath for EMI calculations
     */
    struct CalculateLoanAmt {
        /**
         * @dev User's deposit amount in debt asset
         */
        uint256 depositAmount;
        /**
         * @dev Debt asset decimals
         */
        uint256 debtAssetDecimals;
        /**
         * @dev Target collateral amount
         */
        uint256 collateralAmount;
        /**
         * @dev Collateral asset decimals
         */
        uint256 collateralAssetDecimals;
        /**
         * @dev Collateral price in USD (8 decimals)
         */
        uint256 collateralPriceUSD;
        /**
         * @dev Debt asset price in USD (8 decimals)
         */
        uint256 debtPriceUSD;
        /**
         * @dev Interest rate in RAY (27 decimals)
         */
        uint256 interestRate;
        /**
         * @dev Loan duration in months
         */
        uint256 duration;
        /// @dev Minimum deposit requirement in basis points (e.g., 3300 = 33%)
        uint256 minDepositBps;
        /// @dev Aave V3 flash loan premium in basis points (e.g., 5 = 0.05%)
        uint256 flashLoanPremiumBps;
    }

    // ============ Loan Data Structure ============

    /**
     * @notice Complete loan information stored per LSA
     * @param borrower The address that created and owns this loan
     * @param depositAmount Initial USDC deposit amount (6 decimals)
     * @param loanAmount Total amount borrowed via flash loan (6 decimals)
     * @dev `loanAmount` is a historical record set at creation. It does not track accrued
     *      interest or reflect partial repayments. For live outstanding debt, read the variable
     *      debt token balance via `BitmorLendingPoolLogic.getVDTTokenAmount()`.
     * @param collateralAmount cbBTC amount user wants to achieve (8 decimals)
     * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals)
     * @dev `estimatedMonthlyPayment` is computed once using the max variable borrow rate at loan
     *      creation time. It is not recalculated during the loan lifetime. It serves as the
     *      billing-period divisor for duration tracking and micro-liquidation sizing.
     * @param duration Loan term length in months
     * @param createdAt Unix timestamp when loan was created
     * @param insuranceID Insurance/Order ID for tracking this loan
     * @param lastPaymentTimestamp Timestamp at which last payment was made.
     * @param amountRepaidInCurrentPeriod Accumulated partial repayments within the current billing period (6 decimals)
     * @param status Current lifecycle status of the loan
     */
    struct LoanData {
        address borrower;
        uint256 depositAmount;
        uint256 loanAmount;
        uint256 collateralAmount;
        uint256 estimatedMonthlyPayment;
        uint256 duration;
        uint256 createdAt;
        uint256 insuranceID;
        uint256 lastPaymentTimestamp;
        uint256 amountRepaidInCurrentPeriod;
        LoanStatus status;
    }

    // ============ Loan Status ============

    /**
     * @notice Represents the current state of a loan
     * @dev Active: Loan is ongoing and being repaid
     * @dev Completed: Loan has been fully repaid
     * @dev Liquidated: Loan was liquidated due to insufficient collateral or other reasons
     */
    enum LoanStatus {
        Active,
        Completed,
        Liquidated
    }

    /*
       ____ _____ ____  __     ___   _   _ _   _____   ____    _  _____  _      _______   ______  _____ ____
      | __ )_   _/ ___| \ \   / / \ | | | | | |_   _| |  _ \  / \|_   _|/ \    |_   _\ \ / /  _ \| ____/ ___|
      |  _ \ | || |      \ \ / / _ \| | | | |   | |   | | | |/ _ \ | | / _ \     | |  \ V /| |_) |  _| \___ \
      | |_) || || |___    \ V / ___ \ |_| | |___| |   | |_| / ___ \| |/ ___ \    | |   | | |  __/| |___ ___) |
      |____/ |_| \____|    \_/_/   \_\___/|_____|_|   |____/_/   \_\_/_/   \_\   |_|   |_| |_|   |_____|____/
    */

    /**
     * @notice Represents an allocation instruction for fund reallocation
     * @dev Used in reallocateFunds to specify which strategy and how much to allocate
     */
    struct Allocation {
        /**
         * @notice Index of the strategy in the strategies array
         */
        uint256 index;
        /**
         * @notice Amount of assets to allocate to this strategy
         */
        uint256 amount;
    }

    /**
     * @notice Represents a single tokenized strategy and its constraints
     * @dev Contains strategy address and allocation cap for risk management
     */
    struct Strategy {
        /**
         * @notice Address of the tokenized strategy vault contract
         */
        address strategy;
        /**
         * @notice Maximum number of assets that can be deposited in this strategy
         */
        uint256 cap;
    }

    /**
     * @notice Complete state management for all strategies in the vault
     * @dev Contains strategy storage, indexing, and queue management
     */
    struct StrategyState {
        /**
         * @notice Total number of strategies currently managed by the vault
         */
        uint256 totalStrategies;
        /**
         * @notice Mapping from index to strategy details
         */
        mapping(uint256 index => Strategy strategy) strategies;
        /**
         * @notice Mapping from strategy address to its index (plus one for existence check)
         * @dev 0 means strategy not present, otherwise stores index + 1
         */
        mapping(address strategy => uint256 indexPlusOne) strategyToIndex;
        /**
         * @notice Array defining the order for withdrawing funds from strategies
         * @dev Contains strategy indices, priority order for withdrawals
         */
        uint256[] withdrawQueue;
        /**
         * @notice Array defining the order for supplying funds to strategies
         * @dev Contains strategy indices, priority order for deposits
         */
        uint256[] supplyQueue;
    }

    /**
     * @notice Configuration state for vault fee management
     * @dev Contains fee rates and recipient address for vault operations
     */
    struct VaultState {
        /**
         * @notice Entry fee charged on deposits, expressed in basis points (e.g., 50 = 0.5%)
         */
        uint256 entryFee;
        /**
         * @notice Exit fee charged on withdrawals, expressed in basis points (e.g., 100 = 1%)
         */
        uint256 exitFee;
        /**
         * @notice Address that receives collected entry and exit fees
         */
        address feeRecipient;
        /**
         * @notice Maximum number of strategies that can be added to the vault
         */
        uint256 maxStrategies;
    }
}
