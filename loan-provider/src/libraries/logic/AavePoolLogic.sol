// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IPool} from "../../interfaces/IPool.sol";

library AavePoolLogic {
    uint16 private constant REFERRAL_CODE = 0;

    /**
     * Returns the flash loan premium fee amount in bps.
     * @param aavePool Address of the Lending Pool
     */
    function getFlashLoanPremium(address aavePool) internal view returns (uint256) {
        return IPool(aavePool).FLASHLOAN_PREMIUM_TOTAL();
    }

    function executeFlashLoan(address aavePool, address receiver, address asset, uint256 amount, bytes memory params)
        internal
    {
        IPool(aavePool).flashLoanSimple(receiver, asset, amount, params, REFERRAL_CODE);
    }
}
