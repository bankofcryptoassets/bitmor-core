// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

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

    // ============ Loan Data Structure ============

    /**
     * @notice Complete loan information stored per LSA
     * @dev Field order MUST match loan-provider/src/libraries/types/DataTypes.sol
     *      because getLoanByLSA() returns ABI-encoded data in declaration order.
     * @param borrower The address that created and owns this loan
     * @param duration Loan term length in months
     * @param status Current lifecycle status of the loan
     * @param createdAt Unix timestamp when loan was created
     * @param lastPaymentTimestamp Timestamp at which last payment was made.
     * @param depositAmount Initial USDC deposit amount (6 decimals)
     * @param loanAmount Total amount borrowed via flash loan (6 decimals).
     *        Historical record only — does not track accrued interest.
     *        For live debt, read the variable debt token balance.
     * @param btcAmount cbBTC amount user wants to achieve (8 decimals)
     * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals).
     *        Computed once using max variable borrow rate; not updated during loan lifetime.
     * @param amountRepaidInCurrentPeriod Accumulated partial repayments within the current billing period (6 decimals)
     * @param insuranceID Insurance/Order ID for tracking this loan
     */
    struct LoanData {
        // ── Slot 0 (31B, 1B spare): identity + lifecycle metadata
        address borrower; // 20B
        uint16 duration; // 2B  | months
        LoanStatus status; // 1B  | Active / Completed / Liquidated
        uint32 createdAt; // 4B  | unix timestamp (good until 2106)
        uint32 lastPaymentTimestamp; // 4B  | unix timestamp
        // ── Slot 1 (32B): amounts set at creation
        uint96 depositAmount; // 12B | USDC 6 dec, max ~$79T
        uint96 loanAmount; // 12B | USDC 6 dec
        uint64 btcAmount; // 8B  | cbBTC 8 dec, max ~184B BTC
        // ── Slot 2 (32B): payment tracking
        uint96 estimatedMonthlyPayment; // 12B | USDC 6 dec
        uint96 amountRepaidInCurrentPeriod; // 12B | USDC 6 dec
        // 8B spare
        // ── Slot 3 (32B): insurance ID (kept as uint256 for extensibility)
        uint256 insuranceID;
    }

    // ============ Loan Status ============

    /**
     * @notice Represents the current state of a loan
     * @dev Active: Loan is ongoing and being repaid
     * @dev Completed: Loan has been fully repaid
     * @dev Liquidated: Loan was liquidated due to insufficient collateral or other reasons
     * @dev Status transition invariants (Invariant 2.1):
     * - Status transitions MUST be monotonic: Active -> Completed or Active -> Liquidated
     * - MUST NOT transition from Completed back to Active
     * - MUST NOT transition from Liquidated back to Active
     * - MUST NOT transition from Completed to Liquidated or vice versa
     * - When status is Completed or Liquidated, debt and collateral balances MUST be zero
     */
    enum LoanStatus {
        Active,
        Completed,
        Liquidated
    }
}
