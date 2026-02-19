// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from "../dependencies/openzeppelin/contracts/IERC20.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {SafeERC20} from "../dependencies/openzeppelin/contracts/SafeERC20.sol";

/// @title MockLoanProvider
/// @notice Mock contract simulating the Loan contract for lending-pool tests
/// @dev Allows deposit and borrow operations through the lending pool
contract MockLoanProvider {
    using SafeERC20 for IERC20;

    ILendingPool public pool;

    constructor(address _pool) public {
        pool = ILendingPool(_pool);
    }

    /// @notice Deposits asset into the lending pool on behalf of a user
    /// @param asset The asset to deposit
    /// @param amount The amount to deposit
    /// @param onBehalfOf The user receiving the aTokens
    /// @param referralCode Referral code (unused)
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(pool), amount);
        pool.deposit(asset, amount, onBehalfOf, referralCode);
    }

    /// @notice Borrows asset from the lending pool on behalf of a user
    /// @param asset The asset to borrow
    /// @param amount The amount to borrow
    /// @param interestRateMode The interest rate mode (1 = stable, 2 = variable)
    /// @param referralCode Referral code (unused)
    /// @param onBehalfOf The user receiving the debt
    /// @dev Pool sends borrowed tokens to this contract, we immediately forward to caller
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external {
        pool.borrow(asset, amount, interestRateMode, referralCode, onBehalfOf);
        // Forward borrowed tokens to the caller so they can repay
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    /// @notice Repays debt to the lending pool
    /// @param asset The asset to repay
    /// @param amount The amount to repay
    /// @param rateMode The interest rate mode of the debt
    /// @param onBehalfOf The user whose debt is being repaid
    /// @return The actual amount repaid
    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256) {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        // Reset approval to 0 first to handle existing allowances
        IERC20(asset).safeApprove(address(pool), 0);
        IERC20(asset).safeApprove(address(pool), amount);
        return pool.repay(asset, amount, rateMode, onBehalfOf);
    }
}
