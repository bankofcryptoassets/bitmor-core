// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 * @title ILendingPoolCollateralManager
 * @author Aave
 * @notice Defines the actions involving management of collateral in the protocol.
 *
 */
interface ILendingPoolCollateralManager {
  /**
   * @dev Emitted when a borrower is liquidated
   * @param collateral The address of the collateral being liquidated
   * @param principal The address of the reserve
   * @param user The address of the user being liquidated
   * @param debtToCover The total amount liquidated
   * @param liquidatedCollateralAmount The amount of collateral being liquidated
   * @param liquidator The address of the liquidator
   * @param receiveAToken true if the liquidator wants to receive aTokens, false otherwise
   *
   */
  event LiquidationCall(
    address indexed collateral,
    address indexed principal,
    address indexed user,
    uint256 debtToCover,
    uint256 liquidatedCollateralAmount,
    address liquidator,
    bool receiveAToken
  );

  /**
   * @dev Emitted when a borrower is microliquidated.
   * @param collateral The address of the collateral being liquidated
   * @param principal The address of the reserve
   * @param user The address of the user being liquidated
   * @param debtToCover The total amount liquidated
   * @param liquidatedCollateralAmount The amount of collateral being liquidated
   * @param liquidator The address of the liquidator
   * @param receiveAToken true if the liquidator wants to receive aTokens, false otherwise
   *
   */
  event MicroLiquidationCall(
    address indexed collateral,
    address indexed principal,
    address indexed user,
    uint256 debtToCover,
    uint256 liquidatedCollateralAmount,
    address liquidator,
    bool receiveAToken
  );

  /**
   * @dev Emitted when a reserve is disabled as collateral for an user
   * @param reserve The address of the reserve
   * @param user The address of the user
   *
   */
  event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

  /**
   * @dev Emitted when a reserve is enabled as collateral for an user
   * @param reserve The address of the reserve
   * @param user The address of the user
   *
   */
  event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

  /**
   * @dev Users can invoke this function to liquidate an undercollateralized position.
   * @param collateral The address of the collateral to liquidated
   * @param principal The address of the principal reserve
   * @param user The address of the borrower
   * @param debtToCover The amount of principal that the liquidator wants to repay
   * @param receiveAToken true if the liquidators wants to receive the aTokens, false if
   * he wants to receive the underlying asset directly
   *
   */
  function liquidationCall(
    address collateral,
    address principal,
    address user,
    uint256 debtToCover,
    bool receiveAToken
  ) external returns (uint256, string memory);

  /**
   * @dev Function to micro-liquidate a user who didn't pay its monthly installment for their loan.
   * - The caller (liquidator) pays the monthly installment amount, receives equivalent value of underlying asset used as collateral and increase loan's nextDueDate by 30 days.
   * @param data Microliquidation call data
   */
  function microLiquidationCall(bytes calldata data) external returns (uint256, string memory);

  /**
   * Returns the type of Liquidation
   * 0 => No Liquidation
   * 1 => Full Liquidation
   * 2 => MicroLiquidation
   * @param user Address of the borrower
   */
  function checkTypeOfLiquidation(address user) external returns (uint256);
}
