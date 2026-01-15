// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

library DataTypes {
    // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
    }

    struct UserConfigurationMap {
        uint256 data;
    }

    enum InterestRateMode {
        NONE,
        STABLE,
        VARIABLE
    }

    struct ExecuteInitializeLoanParams {
        address user;
        uint256 depositAmount;
        uint256 premiumAmount;
        uint256 collateralAmount;
        uint256 duration;
        uint256 insuranceID;
        bytes data;
    }

    struct InitializeLoanContext {
        address bitmorPool;
        address oracle;
        address collateralAsset;
        address debtAsset;
        address aavePool;
        address loanVaultFactory;
        address premiumCollector;
        uint256 minCollateralAmt;
        uint256 maxCollateralAmt;
        uint256 loanRepaymentInterval;
    }

    struct ExecuteFLOperationParams {
        address asset;
        uint256 amount;
        uint256 premium;
        address initiator;
        bytes params;
    }

    struct ExecuteFLOperationContext {
        address aavePool;
        address bitmorPool;
        address zQuoter;
        address debtAsset;
        address collateralAsset;
        address swapAdapter;
        address feeCollector;
        address oracle;
        uint256 maxSlippage;
    }

    struct ExecuteRepayParams {
        address lsa;
        uint256 amount;
    }

    struct ExecuteCloseLoanContext {
        address bitmorPool;
        address aavePool;
        address oracle;
        address debtAsset;
        address collateralAsset;
        uint256 preClosureFeeBps;
        uint256 maxSlippage;
    }

    struct ExecuteCloseLoanParams {
        address lsa;
        bool withdrawInCollateralAsset;
    }

    struct CalculateLoanAmountAndMonthlyPayment {
        address bitmorPool;
        address oracle;
        address collateralAsset;
        address debtAsset;
        uint256 depositAmount;
        uint256 debtAssetDecimals;
        uint256 collateralAmount;
        uint256 collateralAssetDecimals;
        uint256 duration;
    }

    struct CalculateLoanAmt {
        uint256 depositAmount;
        uint256 debtAssetDecimals;
        uint256 collateralAmount;
        uint256 collateralAssetDecimals;
        uint256 collateralPriceUSD;
        uint256 debtPriceUSD;
        uint256 interestRate;
        uint256 duration;
    }

    // ============ Loan Data Structure ============

    /**
     * @notice Complete loan information stored per LSA
     * @param borrower The address that created and owns this loan
     * @param depositAmount Initial USDC deposit amount (6 decimals)
     * @param loanAmount Total amount borrowed via flash loan (6 decimals)
     * @param collateralAmount cbBTC amount user wants to achieve (8 decimals)
     * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals)
     * @param duration Loan term length in months
     * @param createdAt Unix timestamp when loan was created
     * @param insuranceID Insurance/Order ID for tracking this loan
     * @param lastPaymentTimestamp Timestamp at which last payment was made.
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

    /// @notice Represents an allocation instruction for fund reallocation
    /// @dev Used in reallocateFunds to specify which strategy and how much to allocate
    struct Allocation {
        /// @notice Index of the strategy in the strategies array
        uint256 index;
        /// @notice Amount of assets to allocate to this strategy
        uint256 amount;
    }

    /// @notice Represents a single tokenized strategy and its constraints
    /// @dev Contains strategy address and allocation cap for risk management
    struct Strategy {
        /// @notice Address of the tokenized strategy vault contract
        address strategy;
        /// @notice Maximum number of assets that can be deposited in this strategy
        uint256 cap;
    }

    /// @notice Complete state management for all strategies in the vault
    /// @dev Contains strategy storage, indexing, and queue management
    struct StrategyState {
        /// @notice Total number of strategies currently managed by the vault
        uint256 totalStrategies;
        /// @notice Mapping from index to strategy details
        mapping(uint256 index => Strategy strategy) strategies;
        /// @notice Mapping from strategy address to its index (plus one for existence check)
        /// @dev 0 means strategy not present, otherwise stores index + 1
        mapping(address strategy => uint256 indexPlusOne) strategyToIndex;
        /// @notice Array defining the order for withdrawing funds from strategies
        /// @dev Contains strategy indices, priority order for withdrawals
        uint256[] withdrawQueue;
        /// @notice Array defining the order for supplying funds to strategies
        /// @dev Contains strategy indices, priority order for deposits
        uint256[] supplyQueue;
    }

    /// @notice Configuration state for vault fee management
    /// @dev Contains fee rates and recipient address for vault operations
    struct VaultState {
        /// @notice Entry fee charged on deposits, expressed in basis points (e.g., 50 = 0.5%)
        uint256 entryFee;
        /// @notice Exit fee charged on withdrawals, expressed in basis points (e.g., 100 = 1%)
        uint256 exitFee;
        /// @notice Address that receives collected entry and exit fees
        address feeRecipient;

        /// @notice Maximum number of strategies that can be added to the vault
        uint256 maxStrategies;
    }
}
