// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LSALogic} from "@bitmor/libraries/logic/LSALogic.sol";

/// @title LSALogicHarness
/// @notice Test harness for LSALogic library that exposes internal functions
/// @dev Allows direct unit testing of library functions without going through Loan.sol
/// @custom:security FOR TESTING ONLY - Exposes internal functions. Never deploy to production.
/// @author Bitmor Protocol
contract LSALogicHarness {
    /// @notice Exposes LSALogic.approveCreditDelegation for testing
    /// @param lsa The Loan Specific Address
    /// @param bitmorPool Bitmor Lending Pool address
    /// @param debtAsset The debt asset (e.g., USDC)
    /// @param amount Amount to delegate
    /// @param delegatee Address that can borrow (typically Protocol address)
    function exposed_approveCreditDelegation(
        address lsa,
        address bitmorPool,
        address debtAsset,
        uint256 amount,
        address delegatee
    ) external {
        LSALogic.approveCreditDelegation(lsa, bitmorPool, debtAsset, amount, delegatee);
    }

    /// @notice Exposes LSALogic.withdrawCollateral for testing
    /// @param lsa The Loan Specific Address holding the collateral position
    /// @param bitmorPool Bitmor Lending Pool address
    /// @param collateralAsset Collateral asset address (e.g., cbBTC)
    /// @param recipient Address to receive the withdrawn collateral
    /// @return amountWithdrawn The actual amount of collateral withdrawn
    function exposed_withdrawCollateral(address lsa, address bitmorPool, address collateralAsset, address recipient)
        external
        returns (uint256 amountWithdrawn)
    {
        return LSALogic.withdrawCollateral(lsa, bitmorPool, collateralAsset, recipient);
    }

    /// @notice Exposes LSALogic.redeemBTC for testing
    /// @param lsa The Loan Specific Address
    /// @param collateralAsset The BTC vault address
    /// @param sharesAmount Amount of shares to redeem
    /// @param recipient Address to receive the underlying BTC
    /// @param slippage_sharesToAsset Minimum acceptable percentage in basis points (e.g., 9900 = 99%)
    /// @return assetsReceived The actual amount of assets received
    function exposed_redeemBTC(
        address lsa,
        address collateralAsset,
        uint256 sharesAmount,
        address recipient,
        uint256 slippage_sharesToAsset
    ) external returns (uint256 assetsReceived) {
        return LSALogic.redeemBTC(lsa, collateralAsset, sharesAmount, recipient, slippage_sharesToAsset);
    }
}
