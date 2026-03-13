// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {Errors} from "../libraries/helpers/Errors.sol";

import {ILoan} from "../interfaces/ILoan.sol";
import {IAutoRepayment} from "../interfaces/IAutoRepayment.sol";

/**
 * @title AutoRepayment
 * @author Bitmor Protocol
 * @notice Contract for automatic repayment of loans
 * @dev Implements IAutoRepayment interface for scheduled loan repayments.
 * Uses UUPS proxy pattern with ERC-7201 namespaced storage.
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
contract AutoRepayment is Initializable, UUPSUpgradeable, IAutoRepayment, AccessManagedUpgradeable {
    using SafeERC20 for IERC20;

    // ============ ERC-7201 Namespaced Storage ============

    bytes32 private constant AUTOREPAYMENT_STORAGE_LOCATION =
        0x7f92c81ed602f5d316d76c0137db9f43ea8643a0e7f06a282198a60578d61c00;

    /// @custom:storage-location erc7201:bitmor.storage.AutoRepayment
    struct AutoRepaymentStorageData {
        /// @dev The Loan contract that processes repayments
        address loan;
        /// @dev The debt asset (USDC) used for repayments
        address debtAsset;
        /// @dev Tracks authorization status for each user-LSA pair
        mapping(address user => mapping(address lsa => bool)) isAuthorized;
    }

    function _getAutoRepaymentStorage() internal pure returns (AutoRepaymentStorageData storage $) {
        assembly {
            $.slot := AUTOREPAYMENT_STORAGE_LOCATION
        }
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /**
     * @notice Initializes the AutoRepayment contract
     * @param _manager Access Manager address for role-based access control
     * @param _loan The Loan contract address
     * @param _debtAsset The debt asset address (USDC)
     */
    function initialize(address _manager, address _loan, address _debtAsset) public initializer {
        if (_loan == address(0) || _debtAsset == address(0)) revert Errors.ZeroAddress();
        __AccessManaged_init(_manager);

        AutoRepaymentStorageData storage $ = _getAutoRepaymentStorage();
        $.loan = _loan;
        $.debtAsset = _debtAsset;
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override restricted {}

    // ============ Public Functions ============

    /**
     * @inheritdoc IAutoRepayment
     */
    function createAutoRepayment(address lsa) external override {
        if (lsa == address(0)) revert Errors.ZeroAddress();

        _getAutoRepaymentStorage().isAuthorized[msg.sender][lsa] = true;

        emit AutoRepayment__RepaymentCreated(lsa, msg.sender);
    }

    /**
     * @inheritdoc IAutoRepayment
     */
    function cancelAutoRepayment(address lsa) external {
        AutoRepaymentStorageData storage $ = _getAutoRepaymentStorage();
        if (!$.isAuthorized[msg.sender][lsa]) revert Errors.InvalidRepaymentHash();
        $.isAuthorized[msg.sender][lsa] = false;
        emit AutoRepayment__RepaymentCancelled(lsa, msg.sender);
    }

    /**
     * @inheritdoc IAutoRepayment
     * @custom:access Restricted to `ARE` (Auto Repayment Executor) role
     */
    function executeAutoRepayment(address lsa, address user, uint256 amount) external restricted {
        AutoRepaymentStorageData storage $ = _getAutoRepaymentStorage();
        if (!$.isAuthorized[user][lsa]) revert Errors.InvalidRepaymentHash();

        IERC20($.debtAsset).safeTransferFrom(user, address(this), amount);
        IERC20($.debtAsset).forceApprove($.loan, amount);
        uint256 amountRepaid = ILoan($.loan).repay(lsa, amount);

        IERC20($.debtAsset).forceApprove($.loan, 0);

        uint256 excess = amount - amountRepaid;
        if (excess > 0) {
            IERC20($.debtAsset).safeTransfer(user, excess);
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

    /**
     * @notice Returns the authorization status for a user-LSA pair
     * @param user The user address
     * @param lsa The LSA address
     * @return True if the user has authorized auto-repayment for the LSA
     */
    function getIsAuthorized(address user, address lsa) external view returns (bool) {
        return _getAutoRepaymentStorage().isAuthorized[user][lsa];
    }
}
