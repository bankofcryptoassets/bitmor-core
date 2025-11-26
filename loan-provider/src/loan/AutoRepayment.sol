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

    mapping(address => mapping(address => bytes32)) public repaymentHash;
    address public immutable i_LOAN_CONTRACT;
    address public immutable i_DEBT_ASSET;
    address public s_executorAddress;

    modifier onlyExecutor() {
        if (msg.sender != s_executorAddress) revert Errors.InvalidExecutor();
        _;
    }

    /**
     * @notice Initializes the AutoRepayment contract
     * @param loanContract Address of the Loan contract
     * @param debtAsset Address of the debt asset (USDC)
     * @param executorAddress Address of the backend executor wallet
     */
    constructor(address loanContract, address debtAsset, address executorAddress) Ownable(msg.sender) {
        if (loanContract == address(0) || debtAsset == address(0)) revert Errors.ZeroAddress();
        i_LOAN_CONTRACT = loanContract;
        i_DEBT_ASSET = debtAsset;
        s_executorAddress = executorAddress;
    }

    /// @inheritdoc IAutoRepayment
    function createRepaymentHash(address lsa) external returns (bytes32) {
        if (lsa == address(0)) revert Errors.ZeroAddress();
        bytes32 hash = keccak256(abi.encodePacked(lsa, msg.sender));
        repaymentHash[lsa][msg.sender] = hash;
        emit AutoRepayment__RepaymentHashCreated(lsa, msg.sender, hash);
        return hash;
    }

    /// @inheritdoc IAutoRepayment
    function executeRepayment(address lsa, address user, uint256 amount) external onlyExecutor {
        if (repaymentHash[lsa][user] != keccak256(abi.encodePacked(lsa, user))) {
            revert Errors.InvalidRepaymentHash();
        }
        IERC20(i_DEBT_ASSET).safeTransferFrom(user, address(this), amount);
        IERC20(i_DEBT_ASSET).forceApprove(i_LOAN_CONTRACT, amount);
        uint256 amountRepaid = ILoan(i_LOAN_CONTRACT).repay(lsa, amount);

        emit AutoRepayment__RepaymentExecuted(lsa, user, amount, amountRepaid);
    }

    /// @inheritdoc IAutoRepayment
    function setExecutorAddress(address executorAddress) external onlyOwner {
        if (executorAddress == address(0)) revert Errors.ZeroAddress();
        s_executorAddress = executorAddress;
        emit AutoRepayment__ExecutorAddressUpdated(executorAddress);
    }
}
