// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {Ownable} from "../dependencies/openzeppelin/Ownable.sol";
import {IERC20} from "../dependencies/openzeppelin/IERC20.sol";
import {SafeERC20} from "../dependencies/openzeppelin/SafeERC20.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {ILoan} from "../interfaces/ILoan.sol";
import {IAutoRepayment} from "../interfaces/IAutoRepayment.sol";

/**
 * @title AutoRepayment
 * @notice Contract for automatic repayment of loans
 * @dev Implements IAutoRepayment interface
 */
contract AutoRepayment is IAutoRepayment, Ownable {
    using SafeERC20 for IERC20;

    mapping(address user => mapping(address lsa => bool)) public isAuthorized;

    address public immutable i_LOAN;
    address public immutable i_DEBT_ASSET;
    address public s_executorAddress;

    constructor(address _loan, address _debtAsset, address _executorAddress) Ownable(msg.sender) {
        i_LOAN = _loan;
        i_DEBT_ASSET = _debtAsset;
        s_executorAddress = _executorAddress;
    }

    /// @inheritdoc IAutoRepayment
    function createRepayment(address lsa) external override {
        if (lsa == address(0)) revert Errors.ZeroAddress();

        isAuthorized[msg.sender][lsa] = true;

        // Return hash for interface compatibility (though not stored)
        emit AutoRepayment__RepaymentHashCreated(lsa, msg.sender);
    }

    /// @inheritdoc IAutoRepayment
    function cancelRepayment(address lsa) external {
        if (!isAuthorized[msg.sender][lsa]) revert Errors.InvalidRepaymentHash();
        isAuthorized[msg.sender][lsa] = false;
        emit AutoRepayment__RepaymentHashCancelled(lsa, msg.sender);
    }

    /// @inheritdoc IAutoRepayment
    function executeRepayment(address lsa, address user, uint256 amount) external {
        if (!isAuthorized[user][lsa]) revert Errors.InvalidRepaymentHash();

        IERC20(i_DEBT_ASSET).safeTransferFrom(user, address(this), amount);
        IERC20(i_DEBT_ASSET).forceApprove(i_LOAN, amount);
        uint256 amountRepaid = ILoan(i_LOAN).repay(lsa, amount);

        emit AutoRepayment__RepaymentExecuted(lsa, user, amount, amountRepaid);
    }

    /// @inheritdoc IAutoRepayment
    function setExecutorAddress(address executorAddress) external override onlyOwner {
        if (executorAddress == address(0)) revert Errors.ZeroAddress();
        s_executorAddress = executorAddress;

        emit AutoRepayment__ExecutorAddressUpdated(executorAddress);
    }
}
