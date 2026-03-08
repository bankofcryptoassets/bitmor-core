// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title BitmorAccessManager
 * @author Bitmor Protocol
 * @notice Central access control manager for the Bitmor Protocol ecosystem
 * @dev Extends OpenZeppelin's AccessManager to provide role-based access control
 * with time-delayed execution for sensitive operations across all protocol contracts.
 *
 * Manages 16 operational roles and 6 guardian roles controlling:
 * - Loan Provider (EXECUTOR, LPCM, LPM_FAST, LPM_SLOW)
 * - BTC Vault (BVM_FAST, BVM_SLOW, BVC, BVA_FAST, BVA_SLOW, BVD)
 * - USDC Vault (UVM_FAST, UVM_SLOW, UVC, UVA)
 * - Auto Repayment (ARE)
 *
 * @custom:security Sensitive operations use 1-day execution delays with guardian cancellation
 * @custom:security Role definitions are specified in RolesData.sol
 */
contract BitmorAccessManager is AccessManager {
    /**
     * @notice Initializes the access manager with an initial admin
     * @param _initialAdmin The address that receives the ADMIN role (role ID 0)
     */
    constructor(address _initialAdmin) AccessManager(_initialAdmin) {}
}
