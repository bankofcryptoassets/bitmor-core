// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IAutoRepayment
 * @author Bitmor Protocol
 * @notice Interface for the AutoRepayment contract
 * @dev Defines functions for automatic loan repayment execution
 */
interface IAutoRepayment {
    // ============ Events ============

    /**
     * @notice Emitted when an auto-repayment is executed
     * @param lsa Loan Specific Address
     * @param user User address whose loan was repaid
     * @param amount Amount requested for repayment
     * @param amountRepaid Actual amount repaid
     */
    event AutoRepayment__RepaymentExecuted(
        address indexed lsa, address indexed user, uint256 amount, uint256 amountRepaid
    );

    /**
     * @notice Emitted when a repayment hash is created
     * @param lsa Loan Specific Address
     * @param user User address whose loan was repaid
     */
    event AutoRepayment__RepaymentCreated(address indexed lsa, address indexed user);

    /**
     * @notice Emitted when a repayment hash is cancelled
     * @param lsa Loan Specific Address
     * @param user User address whose loan was cancelled
     */
    event AutoRepayment__RepaymentCancelled(address indexed lsa, address indexed user);

    /**
     * @notice Emitted when stuck tokens are rescued from the contract
     * @param token The token address rescued
     * @param to The recipient address
     * @param amount The amount rescued
     */
    event AutoRepayment__TokensRescued(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Emitted when excess repayment funds are refunded to the user
     * @param user The user who received the refund
     * @param amount The excess amount refunded
     */
    event AutoRepayment__ExcessRefunded(address indexed user, uint256 amount);

    // ============ Main Functions ============

    /**
     * @notice Creates a repayment hash for a user's loan
     * @dev User must call this to authorize auto-repayments for their loan
     * @param lsa Loan Specific Address
     */
    function createAutoRepayment(address lsa) external;

    /**
     * @notice Cancels a repayment hash for a user's loan
     * @dev User can call this to disable auto-repayments for their loan
     * @param lsa Loan Specific Address
     */
    function cancelAutoRepayment(address lsa) external;

    /**
     * @notice Executes automatic repayment for a user's loan
     * @dev Requires valid authorization and user USDC approval to this contract
     * @param lsa Loan Specific Address
     * @param user User address whose loan is being repaid
     * @param amount Amount to repay
     * @custom:access Restricted to `ARE` (Auto Repayment Executor) role
     */
    function executeAutoRepayment(address lsa, address user, uint256 amount) external;

    /**
     * @notice Rescues stuck tokens from the contract
     * @dev Safety net for accidentally sent tokens or edge-case residuals
     * @param token The ERC20 token address to rescue
     * @param to The recipient address
     * @param amount The amount to rescue
     * @custom:access Restricted to `ARE` (Auto Repayment Executor) role
     */
    function rescueTokens(address token, address to, uint256 amount) external;
}
