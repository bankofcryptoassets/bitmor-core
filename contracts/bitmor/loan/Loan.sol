// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {Ownable} from '../../dependencies/openzeppelin/contracts/Ownable.sol';
import {ReentrancyGuard} from '../../dependencies/openzeppelin/contracts/ReentrancyGuard.sol';
import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {LoanStorage} from './LoanStorage.sol';
import {LoanLogic} from '../libraries/logic/LoanLogic.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {ILoanVaultFactory} from '../interfaces/ILoanVaultFactory.sol';
import {SwapLogic} from '../libraries/logic/SwapLogic.sol';
import {AaveV2InteractionLogic} from '../libraries/logic/AaveV2InteractionLogic.sol';
import {LSALogic} from '../libraries/logic/LSALogic.sol';
import {EscrowLogic} from '../libraries/logic/EscrowLogic.sol';

/**
 * @title Loan
 * @notice Main contract for Bitmor Protocol loan creation and management
 * @dev Handles loan initialization, LSA creation, and data storage
 */
contract Loan is LoanStorage, Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  // ============ Constructor ============

  /**
   * @notice Initializes the Loan contract with protocol addresses and configuration
   * @param _aaveV3Pool Aave V3 pool address for flash loans
   * @param _aaveV2Pool Aave V2 lending pool address for BTC/USDC reserves
   * @param _aaveAddressesProvider Aave V2 addresses provider
   * @param _collateralAsset cbBTC address
   * @param _debtAsset USDC address
   * @param _loanVaultFactory LoanVaultFactory address for creating LSAs
   * @param _escrow Escrow contract address for collateral locking
   * @param _swapAdapter SwapAdapter contract address for token swaps
   * @param _zQuoter zQuoter contract address for Aerodrome price quotes
   * @param _maxLoanAmount Maximum loan amount allowed (6 decimals for USDC)
   */
  constructor(
    address _aaveV3Pool,
    address _aaveV2Pool,
    address _aaveAddressesProvider,
    address _collateralAsset,
    address _debtAsset,
    address _loanVaultFactory,
    address _escrow,
    address _swapAdapter,
    address _zQuoter,
    uint256 _maxLoanAmount
  ) public LoanStorage(_aaveV3Pool, _aaveV2Pool, _aaveAddressesProvider) {
    require(_collateralAsset != address(0), 'Loan: invalid collateral asset');
    require(_debtAsset != address(0), 'Loan: invalid debt asset');
    require(_loanVaultFactory != address(0), 'Loan: invalid factory');
    require(_escrow != address(0), 'Loan: invalid escrow');
    require(_swapAdapter != address(0), 'Loan: invalid swap adapter');
    require(_zQuoter != address(0), 'Loan: invalid zQuoter');
    require(_maxLoanAmount > 0, 'Loan: invalid max loan amount');

    _collateralAsset = _collateralAsset;
    _debtAsset = _debtAsset;
    loanVaultFactory = _loanVaultFactory;
    escrow = _escrow;
    swapAdapter = _swapAdapter;
    zQuoter = _zQuoter;
    maxLoanAmount = _maxLoanAmount;
  }

  // ============ Main Loan Creation ============

  /**
   * @notice Initializes a new loan
   * @dev Creates LSA, calculates loan terms, stores loan data on-chain
   * @param depositAmount USDC deposit amount (6 decimals)
   * @param collateralAmount target/goal cbBTC amount user wants to achieve
   * @param duration Loan duration in months
   * @param insuranceID Insurance/Order ID for tracking this loan
   * @return lsa Address of the created Loan Specific Address
   */
  function initializeLoan(
    uint256 depositAmount,
    uint256 collateralAmount,
    uint256 duration,
    uint256 insuranceID
  ) external nonReentrant returns (address lsa) {
    require(depositAmount > 0, 'Loan: invalid deposit amount');
    require(collateralAmount > 0, 'Loan: invalid collateral amount');
    require(duration > 0, 'Loan: invalid duration');

    // Transfer deposit from user to contract
    IERC20(_debtAsset).safeTransferFrom(msg.sender, address(this), depositAmount);

    uint256 loanAmount;
    // Calculate loan details and store data
    {
      uint256 monthlyPayment;
      uint256 interestRate;
      (loanAmount, monthlyPayment, interestRate) = LoanLogic.calculateLoanAmountAndMonthlyPayment(
        AAVE_V2_POOL,
        ILendingPoolAddressesProvider(AAVE_ADDRESSES_PROVIDER),
        _collateralAsset,
        _debtAsset,
        depositAmount,
        maxLoanAmount,
        collateralAmount,
        duration
      );

      // Create LSA via factory using CREATE2 for deterministic address
      lsa = ILoanVaultFactory(loanVaultFactory).createLoanVault(msg.sender, block.timestamp);

      // Calculate payment timestamps (30 days = 1 month)
      uint256 firstPaymentDue = block.timestamp.add(30 days);
      uint256 finalPaymentDue = block.timestamp.add(duration.mul(30 days));

      // Store loan data on-chain
      _loansByLSA[lsa] = LoanData({
        borrower: msg.sender,
        depositAmount: depositAmount,
        loanAmount: loanAmount,
        collateralAmount: collateralAmount,
        estimatedMonthlyPayment: monthlyPayment,
        duration: duration,
        createdAt: block.timestamp,
        insuranceID: insuranceID,
        nextDueTimestamp: firstPaymentDue,
        lastDueTimestamp: finalPaymentDue,
        status: LoanStatus.Active
      });

      // Update user loan indexing for multi-loan support
      uint256 loanIndex = userLoanCount[msg.sender];
      userLoanAtIndex[msg.sender][loanIndex] = lsa;
      userLoanCount[msg.sender] = loanIndex.add(1);

      // Emit loan creation event
      emit LoanCreated(msg.sender, lsa, loanAmount, collateralAmount, block.timestamp);
    }

    // Flash loan execution flow
    {
      address[] memory assets = new address[](1);
      assets[0] = _debtAsset;

      uint256[] memory amounts = new uint256[](1);
      amounts[0] = loanAmount;

      uint256[] memory modes = new uint256[](1);
      modes[0] = 0; // don't open any debt, just revert if funds can't be transferred from the receiver

      bytes memory params = abi.encode(lsa, collateralAmount);

      ILendingPool(AAVE_V3_POOL).flashLoan(
        address(this), // receiver address
        assets, // assets to borrow
        amounts, // amounts to borrow the assets
        modes, // modes of the debt to open if the flash loan is not returned
        lsa, // onbehalf of address
        params, // params to pass to the receiver
        uint16(0) // referral code
      );
    }

    return lsa;
  }

  // ============ Flash Loan Callback ============

  /**
   * @notice Aave flash loan callback function
   * @dev Called by Aave pool during flash loan execution
   * @param assets Array of asset addresses
   * @param amounts Array of flash loan amounts
   * @param premiums Array of flash loan premiums
   * @param initiator Address that initiated the flash loan
   * @param params Encoded parameters passed to the callback
   * @return Success boolean
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool) {
    require(msg.sender == AAVE_V3_POOL, 'Loan: caller not Aave pool');
    require(initiator == address(this), 'Loan: invalid initiator');

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

    (address lsa, uint256 collateralAmount) = abi.decode(params, (address, uint256));

    // Retrieve loan data from storage
    LoanData storage loan = _loansByLSA[lsa];

    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];
    uint256 totalSwapAmount = loan.depositAmount.add(flashLoanAmount);

    uint256 wbtcReceived = SwapLogic.executeSwap(
      swapAdapter,
      zQuoter,
      _debtAsset, // tokenIn
      _collateralAsset, // tokenOut
      totalSwapAmount, // amountIn
      collateralAmount,
      MAX_SLIPPAGE_BPS
    );

    require(wbtcReceived >= collateralAmount, 'Loan: insufficient cbBTC received');

    uint256 borrowAmount = flashLoanAmount.add(flashLoanPremium);

    LSALogic.approveCreditDelegation(
      lsa,
      AAVE_V2_POOL,
      _debtAsset,
      borrowAmount,
      address(this) // Protocol is the delegatee
    );

    AaveV2InteractionLogic.depositCollateral(AAVE_V2_POOL, _collateralAsset, wbtcReceived, lsa);

    AaveV2InteractionLogic.borrowDebt(AAVE_V2_POOL, _debtAsset, borrowAmount, lsa);

    address acbBTC = AaveV2InteractionLogic.getATokenAddress(AAVE_V2_POOL, _collateralAsset);

    EscrowLogic.lockCollateral(lsa, escrow, acbBTC, wbtcReceived);

    IERC20(_debtAsset).safeApprove(AAVE_V3_POOL, borrowAmount);

    return true;
  }

  // ============ View Functions ============

  /**
   * @notice Retrieves loan data for a specific LSA
   * @param lsa The LSA address
   * @return Loan data struct
   */
  function getLoanByLSA(address lsa) external view returns (LoanData memory) {
    require(_loansByLSA[lsa].borrower != address(0), 'Loan: loan does not exist');
    return _loansByLSA[lsa];
  }

  /**
   * @notice Gets total number of loans created by a user
   * @param user The user address
   * @return Total loan count
   */
  function getUserLoanCount(address user) external view returns (uint256) {
    return userLoanCount[user];
  }

  /**
   * @notice Gets LSA address for user's Nth loan
   * @param user The user address
   * @param index Loan index (0-based)
   * @return LSA address
   */
  function getUserLoanAtIndex(address user, uint256 index) external view returns (address) {
    require(index < userLoanCount[user], 'Loan: index out of bounds');
    return userLoanAtIndex[user][index];
  }

  /**
   * @notice Retrieves all loans for a specific user
   * @param user The user address
   * @return Array of loan data structs
   */
  function getUserAllLoans(address user) external view returns (LoanData[] memory) {
    uint256 count = userLoanCount[user];
    LoanData[] memory loans = new LoanData[](count);

    for (uint256 i = 0; i < count; i++) {
      address lsa = userLoanAtIndex[user][i];
      loans[i] = _loansByLSA[lsa];
    }

    return loans;
  }

  /**
   * @notice Gets the collateral asset address
   * @return cbBTC address
   */
  function getCollateralAsset() external view returns (address) {
    return _collateralAsset;
  }

  /**
   * @notice Gets the debt asset address
   * @return USDC address
   */
  function getDebtAsset() external view returns (address) {
    return _debtAsset;
  }

  // ============ Admin Functions ============

  /**
   * @notice Updates the maximum loan amount
   * @param newMaxLoanAmount New maximum loan amount (6 decimals)
   */
  function setMaxLoanAmount(uint256 newMaxLoanAmount) external onlyOwner {
    require(newMaxLoanAmount > 0, 'Loan: invalid max loan amount');
    uint256 oldAmount = maxLoanAmount;
    maxLoanAmount = newMaxLoanAmount;
    emit MaxLoanAmountUpdated(oldAmount, newMaxLoanAmount);
  }

  /**
   * @notice Updates the loan vault factory address
   * @param newFactory New factory address
   */
  function setLoanVaultFactory(address newFactory) external onlyOwner {
    require(newFactory != address(0), 'Loan: invalid factory');
    loanVaultFactory = newFactory;
  }

  /**
   * @notice Updates the escrow contract address
   * @param newEscrow New escrow address
   */
  function setEscrow(address newEscrow) external onlyOwner {
    require(newEscrow != address(0), 'Loan: invalid escrow');
    escrow = newEscrow;
  }

  /**
   * @notice Updates the swap adapter contract address
   * @param newSwapAdapter New swap adapter address
   */
  function setSwapAdapter(address newSwapAdapter) external onlyOwner {
    require(newSwapAdapter != address(0), 'Loan: invalid swap adapter');
    swapAdapter = newSwapAdapter;
  }

  /**
   * @notice Updates the zQuoter contract address
   * @param newZQuoter New zQuoter address
   */
  function setZQuoter(address newZQuoter) external onlyOwner {
    require(newZQuoter != address(0), 'Loan: invalid zQuoter');
    zQuoter = newZQuoter;
  }

  /**
   * @notice Updates loan status
   * @dev Used by repayment and liquidation flows
   * @param lsa The LSA address
   * @param newStatus The new loan status
   */
  function updateLoanStatus(address lsa, LoanStatus newStatus) external onlyOwner {
    require(_loansByLSA[lsa].borrower != address(0), 'Loan: loan does not exist');
    LoanStatus oldStatus = _loansByLSA[lsa].status;
    _loansByLSA[lsa].status = newStatus;
    emit LoanStatusUpdated(lsa, oldStatus, newStatus);
  }
}
