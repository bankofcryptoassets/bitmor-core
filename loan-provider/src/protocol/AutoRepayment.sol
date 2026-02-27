// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AccessManaged} from "@openzeppelin/access/manager/AccessManaged.sol";

import {Errors} from "../libraries/helpers/Errors.sol";

import {ILoan} from "../interfaces/ILoan.sol";
import {IAutoRepayment} from "../interfaces/IAutoRepayment.sol";

/**
 * @title AutoRepayment
 * @author Bitmor Protocol
 * @notice Contract for automatic repayment of loans
 * @dev Implements IAutoRepayment interface for scheduled loan repayments.
 *
 * ## Overview
 * Enables users to authorize automatic repayments for their loans. An off-chain
 * executor can then trigger repayments when due, pulling funds from users who
 * have pre-approved the contract.
 *
 * ## User Flow
 * 1. User calls `createAutoRepayment(lsa)` to authorize auto-repayments for a loan
 * 2. User approves this contract to spend USDC
 * 3. Executor calls `executeAutoRepayment()` when payment is due
 * 4. User can call `cancelAutoRepayment()` to revoke authorization
 *
 * @custom:security Executor role required for executing repayments
 * @custom:security Users must explicitly authorize each LSA for auto-repayment
 */
contract AutoRepayment is IAutoRepayment, AccessManaged {
    using SafeERC20 for IERC20;

    /**
     * @notice Tracks authorization status for each user-LSA pair
     * @dev `isAuthorized[user][lsa]` = true means user has authorized auto-repayment for that LSA
     */
    mapping(address user => mapping(address lsa => bool)) public isAuthorized;

    /**
     * @notice The Loan contract that processes repayments
     */
    address public immutable i_LOAN;

    /**
     * @notice The debt asset (USDC) used for repayments
     */
    address public immutable i_DEBT_ASSET;

    /**
     * @notice Initializes the AutoRepayment contract
     * @param _manager Access Manager address for role-based access control
     * @param _loan The Loan contract address
     * @param _debtAsset The debt asset address (USDC)
     */
    constructor(address _manager, address _loan, address _debtAsset) AccessManaged(_manager) {
        i_LOAN = _loan;
        i_DEBT_ASSET = _debtAsset;
    }

    /**
     * @inheritdoc IAutoRepayment
     */
    function createAutoRepayment(address lsa) external override {
        if (lsa == address(0)) revert Errors.ZeroAddress();

        isAuthorized[msg.sender][lsa] = true;

        // Return hash for interface compatibility (though not stored)
        emit AutoRepayment__RepaymentCreated(lsa, msg.sender);
    }

    /**
     * @inheritdoc IAutoRepayment
     */
    function cancelAutoRepayment(address lsa) external {
        if (!isAuthorized[msg.sender][lsa]) revert Errors.InvalidRepaymentHash();
        isAuthorized[msg.sender][lsa] = false;
        emit AutoRepayment__RepaymentCancelled(lsa, msg.sender);
    }

    /**
     * @inheritdoc IAutoRepayment
     * @custom:access Restricted to `ARE` (Auto Repayment Executor) role
     */
    function executeAutoRepayment(address lsa, address user, uint256 amount) external restricted {
        if (!isAuthorized[user][lsa]) revert Errors.InvalidRepaymentHash();

        IERC20(i_DEBT_ASSET).safeTransferFrom(user, address(this), amount);
        IERC20(i_DEBT_ASSET).forceApprove(i_LOAN, amount);
        uint256 amountRepaid = ILoan(i_LOAN).repay(lsa, amount);

        IERC20(i_DEBT_ASSET).forceApprove(i_LOAN, 0);

        uint256 excess = amount - amountRepaid;
        if (excess > 0) {
            IERC20(i_DEBT_ASSET).safeTransfer(user, excess);
            emit AutoRepayment__ExcessRefunded(user, excess);
        }

        emit AutoRepayment__RepaymentExecuted(lsa, user, amount, amountRepaid);
    }

    /**
     * @inheritdoc IAutoRepayment
     * @custom:access Restricted to `ARE` (Auto Repayment Executor) role
     */
    function rescueTokens(address token, address to, uint256 amount) external restricted {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();

        IERC20(token).safeTransfer(to, amount);

        emit AutoRepayment__TokensRescued(token, to, amount);
    }
}
