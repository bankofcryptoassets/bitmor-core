// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Errors
 * @author Bitmor Protocol
 * @notice Custom error definitions for the Bitmor Protocol
 * @dev All custom errors used across the protocol are defined here for consistency
 * and gas efficiency. Custom errors are more gas-efficient than require strings.
 *
 * ## Error Categories
 * - **Validation Errors**: ZeroAmount, ZeroAddress, InvalidInputs
 * - **Loan Errors**: LoanDoesNotExists, LoanIsNotActive, InsufficientCollateral
 * - **Access Errors**: UnauthorizedCaller, CallerIsNotAAVEPool, InvalidExecutor
 * - **Vault Errors**: MaxStrategiesReached, StrategyNotFound, AllCapsReached
 */
library Errors {
    // ============ Validation Errors ============

    /**
     * @notice Thrown when a zero amount is provided where a positive value is required
     */
    error ZeroAmount();

    /**
     * @notice Thrown when the zero address is provided where a valid address is required
     */
    error ZeroAddress();

    // ============ Loan Errors ============

    /**
     * @notice Thrown when attempting to access a loan that does not exist for the given LSA
     */
    error LoanDoesNotExists();

    /**
     * @notice Thrown when attempting to operate on a loan that is not in Active status
     */
    error LoanIsNotActive();

    /**
     * @notice Thrown when loan duration is zero or exceeds the maximum allowed
     */
    error Loan__InvalidDuration();

    /**
     * @notice Thrown when array index is out of valid bounds
     */
    error IndexOutOfBounds();

    /**
     * @notice Thrown when oracle returns zero or invalid price for an asset
     */
    error InvalidAssetPrice();

    /**
     * @notice Thrown when oracle price is older than the configured maximum staleness threshold
     */
    error StaleOraclePrice();

    // ============ Flash Loan Errors ============

    /**
     * @notice Thrown when flash loan callback is called by an address other than Aave V3 Pool
     */
    error CallerIsNotAAVEPool();

    /**
     * @notice Thrown when flash loan initiator is not the expected contract
     */
    error WrongFLInitiator();

    // ============ Swap Errors ============

    /**
     * @notice Thrown when swap output is less than the minimum acceptable amount
     */
    error LessThanMinimumAmtReceived();

    // ============ Access Control Errors ============

    /**
     * @notice Thrown when caller is not authorized to perform the operation
     */
    error UnauthorizedCaller();

    // ============ Collateral and Deposit Errors ============

    /**
     * @notice Thrown when collateral value is insufficient for the requested operation
     */
    error InsufficientCollateral();

    /**
     * @notice Thrown when deposit amount is below the minimum required (33%)
     */
    error InsufficientDeposit();

    /**
     * @notice Thrown when requested cbBTC amount exceeds the maximum allowed (1 BTC)
     */
    error GreaterThanMaxBTCAllowed();

    /**
     * @notice Thrown when requested cbBTC amount is below the minimum allowed (0.01 BTC)
     */
    error LessThanMinBTCAllowed();

    /**
     * @notice Thrown when collateral withdrawal from Bitmor Pool fails
     */
    error CollateralWithdrawFailed();

    // ============ Auto-Repayment Errors ============

    /**
     * @notice Thrown when executor address is invalid for auto-repayment
     */
    error InvalidExecutor();

    /**
     * @notice Thrown when repayment hash is invalid or not authorized
     */
    error InvalidRepaymentHash();

    // ============ General Validation Errors ============

    /**
     * @notice Thrown when invalid input parameters are provided to a function
     */
    error InvalidInputs();

    /**
     * @notice Thrown when deposit amount is below the minimum required threshold
     */
    error MinimumAssetRequired();

    /**
     * @notice Thrown when funds cannot be withdrawn due to constraints
     */
    error CannotWithdrawFunds();

    /**
     * @notice Thrown when account has insufficient balance for the operation
     */
    error InsufficientBalance();

    // ============ Vault Strategy Errors ============

    /**
     * @notice Thrown when attempting to add strategies beyond the maximum allowed
     */
    error MaxStrategiesReached();

    /**
     * @notice Thrown when attempting to add a strategy that already exists
     */
    error StrategyAlreadyAdded();

    /**
     * @notice Thrown when strategy's asset doesn't match vault's underlying asset
     */
    error WrongBaseAsset();

    /**
     * @notice Thrown when attempting operations on a strategy that doesn't exist
     */
    error StrategyNotFound();

    /**
     * @notice Thrown when attempting to set a cap to the same value it already has
     */
    error NoChangeInCap();

    /**
     * @notice Thrown when all strategies have reached their allocation caps
     */
    error AllCapsReached();

    /**
     * @notice Thrown when there's insufficient liquidity for withdrawal operations
     */
    error NotEnoughLiquidity();

    /**
     * @notice Thrown when attempting to set a strategy cap to zero
     */
    error ZeroCap();

    /**
     * @notice Thrown when array lengths don't match expected values
     */
    error WrongLength();

    /**
     * @notice Thrown when a strategy appears multiple times in a queue
     * @param strategyIndex The index of the duplicated strategy
     */
    error DuplicateStrategy(uint256 strategyIndex);

    /**
     * @notice Thrown when attempting to remove a strategy that still has asset balance
     * @param strategyIndex The index of the strategy with non-zero balance
     */
    error InvalidStrategyRemovalWithNonZeroAssetBalance(uint256 strategyIndex);

    /**
     * @notice Thrown when attempting to remove a strategy that still has allocation cap
     * @param strategyIndex The index of the strategy with non-zero cap
     */
    error InvalidStrategyRemovalWithNonZeroCap(uint256 strategyIndex);

    /**
     * @notice Thrown when a strategy in a queue has zero allocation cap
     * @param strategyIndex The index of the strategy with zero cap
     */
    error StrategyWithZeroCap(uint256 strategyIndex);

    /**
     * @notice Thrown when attempting to supply more than a strategy's cap allows
     * @param strategyIndex The index of the strategy that would exceed its cap
     */
    error SupplyCapExceeded(uint256 strategyIndex);

    /**
     * @notice Thrown when reallocation parameters are invalid or inconsistent
     */
    error InvalidReallocation();

    /**
     * @notice Thrown when fee exceeds the maximum allowed percentage
     */
    error ExceedMaxFee();

    /// @notice Thrown when slippage exceeds while converting shares to assets.
    error SlippageExceededWhileConvertingToAssets();

    /// @notice Thrown when a fee parameter is set to an invalid value
    error InvalidFee();

    /// @notice Thrown when the exact-output swap requires more input tokens than available.
    error LessAmountForExactOutSwap();

    /// @notice Thrown when slippage exceeds the allowed value.
    error InvalidSlippage();

    /// @notice Thrown when cbBTC-to-USDC swap output is insufficient to cover flash loan repayment.
    error InsufficientSwapOutput();

    /// @notice Thrown when a non-zero fee is set while the fee recipient is still address(0)
    error Vault__FeeRecipientNotSet();

    // ============ LoanVault Errors ============

    /// @notice Thrown when LoanVault owner address is zero during initialization
    error LoanVault__InvalidOwner();

    /// @notice Thrown when LoanVault borrower address is zero during initialization
    error LoanVault__InvalidBorrower();

    /// @notice Thrown when LoanVault token address is zero
    error LoanVault__InvalidToken();

    /// @notice Thrown when LoanVault spender address is zero
    error LoanVault__InvalidSpender();

    /// @notice Thrown when LoanVault recipient address is zero
    error LoanVault__InvalidToAddress();

    /// @notice Thrown when LoanVault execute target address is zero
    error LoanVault__InvalidTarget();

    /// @notice Thrown when LoanVault external call execution fails
    error LoanVault__ExecutionFailed();

    /// @notice Thrown when LoanVault has already been initialized
    error LoanVault__AlreadyInitialized();

    /// @notice Thrown when caller is not the LoanVault owner
    error LoanVault__CallerIsNotOwner();

    // ============ LSALogic Errors ============

    /// @notice Thrown when variable debt token address is zero
    error LSALogic__InvalidDebtToken();

    /// @notice Thrown when surplus collateral claim is attempted while the LSA still has outstanding debt
    error LSALogic__OutstandingDebtExists();

    // ============ Loan Surplus Claim Errors ============

    /// @notice Thrown when `claimSurplusCollateral` is called by an address other than the loan borrower
    error Loan__OnlyBorrower();

    /// @notice Thrown when `claimSurplusCollateral` is called on a loan that is still Active
    error Loan__InvalidLoanStatus();

    /// @notice Thrown when `claimSurplusCollateral` is called and either BLP or BTC vault returns 0.
    error Loan__ClaimingSurplusCollateralFailed();
}
