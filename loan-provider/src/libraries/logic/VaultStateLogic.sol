// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title VaultStateLogic
 * @author Bitmor Protocol
 * @notice Library for managing vault configuration state including fees and recipient settings
 * @dev Simple state update functions for vault configuration management.
 * Uses SafeCast for downcasting uint256 params to packed storage types.
 */
library VaultStateLogic {
    /**
     * @notice Updates the entry fee charged on deposits
     * @param s The vault state storage reference
     * @param newEntryFee The new entry fee in basis points (e.g., 50 = 0.5%)
     */
    function updateEntryFee(DataTypes.VaultState storage s, uint256 newEntryFee) internal {
        s.entryFee = SafeCast.toUint16(newEntryFee);
    }

    /**
     * @notice Updates the exit fee charged on withdrawals
     * @param s The vault state storage reference
     * @param newExitFee The new exit fee in basis points (e.g., 100 = 1%)
     */
    function updateExitFee(DataTypes.VaultState storage s, uint256 newExitFee) internal {
        s.exitFee = SafeCast.toUint16(newExitFee);
    }

    /**
     * @notice Updates the address that receives collected fees
     * @param s The vault state storage reference
     * @param newFeeRecipient The new fee recipient address
     */
    function updateFeeRecipient(DataTypes.VaultState storage s, address newFeeRecipient) internal {
        s.feeRecipient = newFeeRecipient;
    }
}
