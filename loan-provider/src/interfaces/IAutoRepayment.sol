// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title IAutoRepayment
 * @notice Interface for the AutoRepayment contract
 * @dev Defines functions for automatic loan repayment execution
 */
interface IAutoRepayment {
    // ============ Events ============

    /**
     * @notice Emitted when a auto-repayment is executed
     * @param lsa Loan Specific Address
     * @param user User address whose loan was repaid
     * @param amount Amount requested for repayment
     * @param amountRepaid Actual amount repaid
     */
    event AutoRepayment__RepaymentExecuted(
        address indexed lsa, address indexed user, uint256 amount, uint256 amountRepaid
    );

    /**
     * @notice Emitted when the executor address is updated
     * @param executorAddress New executor address
     */
    event AutoRepayment__ExecutorAddressUpdated(address indexed executorAddress);

    /**
     * @notice Emitted when a repayment hash is created
     * @param lsa Loan Specific Address
     * @param user User address whose loan was repaid
     */
    event AutoRepayment__RepaymentHashCreated(address indexed lsa, address indexed user);

    /**
     * @notice Emitted when a repayment hash is cancelled
     * @param lsa Loan Specific Address
     * @param user User address whose loan was cancelled
     */
    event AutoRepayment__RepaymentHashCancelled(address indexed lsa, address indexed user);

    // ============ Main Functions ============

    /**
     * @notice Creates a repayment hash for a user's loan
     * @dev User must call this to authorize auto-repayments for their loan
     * @param lsa Loan Specific Address
     */
    function createRepayment(address lsa) external;

    /**
     * @notice Cancels a repayment hash for a user's loan
     * @dev User can call this to disable auto-repayments for their loan
     * @param lsa Loan Specific Address
     */
    function cancelRepayment(address lsa) external;

    /**
     * @notice Executes automatic repayment for a user's loan
     * @dev Can only be called by the executor address
     * @dev Requires valid repayment hash and user USDC approval
     * @param lsa Loan Specific Address
     * @param user User address whose loan is being repaid
     * @param amount Amount to repay
     */
    function executeRepayment(address lsa, address user, uint256 amount) external;

    /**
     * @notice Updates the executor address
     * @dev Can only be called by the contract owner
     * @param executorAddress New executor address
     */
    function setExecutorAddress(address executorAddress) external;
}
