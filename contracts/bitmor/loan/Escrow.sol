// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IEscrow} from '../interfaces/IEscrow.sol';

/**
 * @title Escrow
 * @notice Manages locked collateral (acbBTC) for LSAs in the Bitmor Protocol
 * @dev Holds aTokens from Aave V2
 */
contract Escrow is IEscrow {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  // ============ State Variables ============

  /**
   * @notice Loan contract address that can lock/unlock collateral
   */
  address public loanContract;

  /**
   * @notice acbBTC token address
   */
  address public immutable acbBTC;

  /**
   * @notice Tracks locked collateral amounts per LSA
   */
  mapping(address => uint256) private _lockedCollateral;

  // ============ Events ============

  /**
   * @notice Emitted when collateral is locked in escrow
   * @param lsa LSA address that owns the locked collateral
   * @param amount Amount locked (8 decimals)
   */
  event CollateralLocked(address indexed lsa, uint256 amount);

  /**
   * @notice Emitted when collateral is unlocked from escrow
   * @param lsa LSA address receiving the unlocked collateral
   * @param amount Amount unlocked (8 decimals)
   */
  event CollateralUnlocked(address indexed lsa, uint256 amount);

  // ============ Modifiers ============

  /**
   * @notice Restricts access to only the Loan contract
   */
  modifier onlyLoanContract() {
    require(msg.sender == loanContract, 'Escrow: caller is not loan contract');
    _;
  }

  // ============ Events ============

  event LoanContractSet(address indexed loanContract);

  // ============ Constructor ============

  /**
   * @notice Initializes the Escrow contract with acbBTC and loan contract addresses
   * @param _acbBTC acbBTC token address
   * @param _loanContract Loan contract address authorized to lock/unlock collateral
   */
  constructor(address _acbBTC, address _loanContract) public {
    require(_acbBTC != address(0), 'Escrow: invalid acbBTC');
    require(_loanContract != address(0), 'Escrow: invalid loan contract');
    acbBTC = _acbBTC;
    loanContract = _loanContract;
  }

  // ============ Core Functions ============

  /**
   * @notice Locks collateral from LSA into Escrow
   * @dev Called by Protocol during loan creation via EscrowLogic
   * @dev LSA must have approved Escrow to spend acbBTC before calling
   * @param lsa LSA address holding the acbBTC
   * @param amount Amount to lock (8 decimals)
   */
  function lockCollateral(address lsa, uint256 amount) external override onlyLoanContract {
    require(lsa != address(0), 'Escrow: invalid lsa');
    require(amount > 0, 'Escrow: invalid amount');

    IERC20(acbBTC).safeTransferFrom(lsa, address(this), amount);

    _lockedCollateral[lsa] = _lockedCollateral[lsa].add(amount);

    emit CollateralLocked(lsa, amount);
  }

  /**
   * @notice Unlocks collateral from Escrow back to LSA
   * @dev Called during loan repayment or liquidation
   * @param lsa LSA address to receive the acbBTC
   * @param amount Amount to unlock (8 decimals)
   */
  function unlockCollateral(address lsa, uint256 amount) external override onlyLoanContract {
    require(lsa != address(0), 'Escrow: invalid lsa');
    require(amount > 0, 'Escrow: invalid amount');
    require(_lockedCollateral[lsa] >= amount, 'Escrow: insufficient locked collateral');

    _lockedCollateral[lsa] = _lockedCollateral[lsa].sub(amount);

    IERC20(acbBTC).safeTransfer(lsa, amount);

    emit CollateralUnlocked(lsa, amount);
  }

  // ============ View Functions ============

  /**
   * @notice Gets the locked collateral amount for an LSA
   * @param lsa LSA address
   * @return Locked amount (8 decimals)
   */
  function getLockedAmount(address lsa) external view override returns (uint256) {
    return _lockedCollateral[lsa];
  }
}
