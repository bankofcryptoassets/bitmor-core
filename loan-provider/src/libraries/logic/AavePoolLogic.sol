// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IPool} from "../../interfaces/IPool.sol";

/**
 * @title AavePoolLogic
 * @author Bitmor Protocol
 * @notice Library for Aave V3 pool interactions
 * @dev Wraps Aave V3 pool functions for flash loan operations.
 * Used by `LoanLogic` for loan initialization and `CloseLoanLogic` for loan closure.
 * @custom:security Flash loan callbacks are validated in `FlashLoanLogic`, not here
 */
library AavePoolLogic {
    /**
     * @dev Referral code for Aave operations (0 = no referral)
     */
    uint16 private constant REFERRAL_CODE = 0;

    /**
     * @notice Returns the flash loan premium fee amount in basis points
     * @param aavePool Address of the Aave V3 Pool
     * @return The flash loan premium in basis points (e.g., 5 = 0.05%)
     */
    function getFlashLoanPremium(address aavePool) internal view returns (uint256) {
        return IPool(aavePool).FLASHLOAN_PREMIUM_TOTAL();
    }

    /**
     * @notice Executes a simple flash loan from Aave V3
     * @dev The `receiver` contract must implement `IFlashLoanSimpleReceiver.executeOperation`.
     * The callback must approve the Aave pool to pull back `amount + premium` before returning.
     * @param aavePool Address of the Aave V3 Pool
     * @param receiver Address that receives the flash loaned assets and callback
     * @param asset Address of the asset to flash loan
     * @param amount Amount of asset to flash loan
     * @param params Encoded parameters to pass to the receiver's callback
     * @custom:security The receiver callback must validate `msg.sender` is the Aave pool and `initiator` is trusted
     */
    function executeFlashLoan(address aavePool, address receiver, address asset, uint256 amount, bytes memory params)
        internal
    {
        IPool(aavePool).flashLoanSimple(receiver, asset, amount, params, REFERRAL_CODE);
    }
}
