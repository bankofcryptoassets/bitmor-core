// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ILoanVault} from '../../interfaces/ILoanVault.sol';

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
   * @param aToken acbBTC token address
   * @param amount Amount to lock (8 decimals)
   */
  function lockCollateral(address lsa, address escrow, address aToken, uint256 amount) internal {
    require(lsa != address(0), 'EscrowLogic: invalid lsa');
    require(escrow != address(0), 'EscrowLogic: invalid escrow');
    require(aToken != address(0), 'EscrowLogic: invalid aToken');
    require(amount > 0, 'EscrowLogic: invalid amount');

    // LSA approves Escrow to spend acbBTC
    bytes memory approveData = abi.encodeWithSignature('approve(address,uint256)', escrow, amount);

    ILoanVault(lsa).execute(aToken, approveData);

    // Call Escrow.lockCollateral()
    (bool success, ) = escrow.call(
      abi.encodeWithSignature('lockCollateral(address,address,uint256)', lsa, aToken, amount)
    );

    require(success, 'EscrowLogic: lock failed');
  }

  /**
   * @notice Unlocks collateral from Escrow back to LSA
   * @dev Called during loan repayment or liquidation
   * @param lsa LSA address to receive acbBTC
   * @param escrow Escrow contract address
   * @param aToken acbBTC token address
   * @param amount Amount to unlock (8 decimals)
   */
  function unlockCollateral(address lsa, address escrow, address aToken, uint256 amount) internal {
    require(lsa != address(0), 'EscrowLogic: invalid lsa');
    require(escrow != address(0), 'EscrowLogic: invalid escrow');
    require(aToken != address(0), 'EscrowLogic: invalid aToken');
    require(amount > 0, 'EscrowLogic: invalid amount');

    // Call Escrow.unlockCollateral()
    (bool success, ) = escrow.call(
      abi.encodeWithSignature('unlockCollateral(address,address,uint256)', lsa, aToken, amount)
    );

    require(success, 'EscrowLogic: unlock failed');
  }
}
