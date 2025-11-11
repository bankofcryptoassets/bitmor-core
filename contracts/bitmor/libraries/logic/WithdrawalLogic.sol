// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ILoanVault} from '../../interfaces/ILoanVault.sol';
import {EscrowLogic} from './EscrowLogic.sol';

/**
 * @title WithdrawalLogic
 * @notice Handles collateral withdrawal from LSA
 */
library WithdrawalLogic {
  /**
   * @notice Withdraws collateral from LSA to user's wallet
   * @param lsa The Loan Specific Address
   * @param aaveV2Pool Aave V2 lending pool address
   * @param escrow Escrow contract address
   * @param cbBTC cbBTC token address (underlying asset)
   * @param amount Amount to withdraw (8 decimals)
   * @param recipient User's wallet address to receive cbBTC
   * @return amountWithdrawn Actual amount of cbBTC withdrawn
   */
  function withdrawCollateral(
    address lsa,
    address aaveV2Pool,
    address escrow,
    address cbBTC,
    uint256 amount,
    address recipient
  ) internal returns (uint256 amountWithdrawn) {
    require(lsa != address(0), 'WithdrawalLogic: invalid lsa');
    require(recipient != address(0), 'WithdrawalLogic: invalid recipient');
    require(amount > 0, 'WithdrawalLogic: invalid amount');

    EscrowLogic.unlockCollateral(lsa, escrow, amount);

    // LSA calls aaveV2Pool.withdraw(cbBTC, amount, recipient)
    // This will:
    //   - Burn acbBTC from LSA
    //   - Send cbBTC to recipient
    //   - Validate health factor > 1.0 (Aave's built-in check) @Note @TODO: This is something which we may have to remove as we have insurance in place.
    bytes memory withdrawData = abi.encodeWithSignature(
      'withdraw(address,uint256,address)',
      cbBTC,
      amount,
      recipient
    );

    bytes memory result = ILoanVault(lsa).execute(aaveV2Pool, withdrawData);

    // Decode the actual amount withdrawn
    amountWithdrawn = abi.decode(result, (uint256));

    require(amountWithdrawn > 0, 'WithdrawalLogic: withdrawal failed');

    return amountWithdrawn;
  }
}
