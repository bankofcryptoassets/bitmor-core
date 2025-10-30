// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ILoanVault} from '../../interfaces/ILoanVault.sol';
import {IEscrow} from '../../interfaces/IEscrow.sol';

/**
 * @title EscrowLogic
 * @notice Handles collateral locking in Escrow contract
 */
library EscrowLogic {
  /**
   * @notice Locks collateral (acbBTC) from LSA into Escrow
   * @dev LSA approves Escrow, then Escrow pulls acbBTC
   * @param lsa LSA address holding acbBTC
   * @param escrow Escrow contract address
   * @param acbBTC acbBTC token address
   * @param amount Amount to lock (8 decimals)
   */
  function lockCollateral(address lsa, address escrow, address acbBTC, uint256 amount) internal {
    require(lsa != address(0), 'EscrowLogic: invalid lsa');
    require(escrow != address(0), 'EscrowLogic: invalid escrow');
    require(acbBTC != address(0), 'EscrowLogic: invalid acbBTC');
    require(amount > 0, 'EscrowLogic: invalid amount');

    bytes memory approveData = abi.encodeWithSignature('approve(address,uint256)', escrow, amount);

    ILoanVault(lsa).execute(acbBTC, approveData);

    IEscrow(escrow).lockCollateral(lsa, amount);
  }

  /**
   * @notice Unlocks collateral from Escrow back to LSA
   * @dev Called during loan repayment or liquidation
   * @param lsa LSA address to receive acbBTC
   * @param escrow Escrow contract address
   * @param amount Amount to unlock (8 decimals)
   */
  function unlockCollateral(address lsa, address escrow, uint256 amount) internal {
    require(lsa != address(0), 'EscrowLogic: invalid lsa');
    require(escrow != address(0), 'EscrowLogic: invalid escrow');
    require(amount > 0, 'EscrowLogic: invalid amount');

    IEscrow(escrow).unlockCollateral(lsa, amount);
  }
}
