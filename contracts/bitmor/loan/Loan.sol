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
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import {ILoanVaultFactory} from '../interfaces/ILoanVaultFactory.sol';
import {SwapLogic} from '../libraries/logic/SwapLogic.sol';
import {AaveV2InteractionLogic} from '../libraries/logic/AaveV2InteractionLogic.sol';
import {LSALogic} from '../libraries/logic/LSALogic.sol';
import {WithdrawalLogic} from '../libraries/logic/WithdrawalLogic.sol';
import {IEscrow} from '../interfaces/IEscrow.sol';
import {ILoan} from '../interfaces/ILoan.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';
import {RepayLogic} from '../libraries/logic/RepayLogic.sol';

/**
 * @title Loan
 * @notice Main contract for Bitmor Protocol loan creation and management
 */
contract Loan is LoanStorage, ILoan, Ownable, ReentrancyGuard {
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
   * @param _swapAdapter SwapAdapter contract address for token swaps
   * @param _zQuoter zQuoter contract address (address(0) for Uniswap V4 on Base Sepolia)
   * @param _maxLoanAmount Maximum loan amount allowed (6 decimals for USDC)
   */
  constructor(
    address _aaveV3Pool,
    address _aaveV2Pool,
    address _aaveAddressesProvider,
    address _collateralAsset,
    address _debtAsset,
    address _swapAdapter,
    address _zQuoter,
    uint256 _maxLoanAmount
  )
    public
    LoanStorage(_aaveV3Pool, _aaveV2Pool, _aaveAddressesProvider, _collateralAsset, _debtAsset)
  {
    require(_swapAdapter != address(0), 'Loan: invalid swap adapter');
    require(_maxLoanAmount > 0, 'Loan: invalid max loan amount');

    s_swapAdapter = _swapAdapter;
    s_zQuoter = _zQuoter;
    s_maxLoanAmount = _maxLoanAmount;
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
  ) external override nonReentrant returns (address lsa) {
    require(depositAmount > 0, 'Loan: invalid deposit amount');
    require(collateralAmount > 0, 'Loan: invalid collateral amount');
    require(duration > 0, 'Loan: invalid duration');

    // Transfer deposit from user to contract
    IERC20(i_debtAsset).safeTransferFrom(msg.sender, address(this), depositAmount);

    uint256 loanAmount;
    // Calculate loan details and store data
    {
      uint256 monthlyPayment;
      uint256 interestRate;
      (loanAmount, monthlyPayment, interestRate) = LoanLogic.calculateLoanAmountAndMonthlyPayment(
        i_AAVE_V2_POOL,
        ILendingPoolAddressesProvider(i_AAVE_ADDRESSES_PROVIDER),
        i_collateralAsset,
        i_debtAsset,
        depositAmount,
        s_maxLoanAmount,
        collateralAmount,
        duration
      );

      // Create LSA via factory using CREATE2 for deterministic address
      lsa = ILoanVaultFactory(s_loanVaultFactory).createLoanVault(msg.sender, block.timestamp);

      // Calculate payment timestamps (30 days = 1 month)
      uint256 firstPaymentDue = block.timestamp.add(LOAN_REPAYMENT_INTERVAL);
      uint256 finalPaymentDue = block.timestamp.add(duration.mul(LOAN_REPAYMENT_INTERVAL));

      // Store loan data on-chain
      s_loansByLSA[lsa] = DataTypes.LoanData({
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
        status: DataTypes.LoanStatus.Active
      });

      // Update user loan indexing for multi-loan support
      uint256 loanIndex = s_userLoanCount[msg.sender];
      s_userLoanAtIndex[msg.sender][loanIndex] = lsa;
      s_userLoanCount[msg.sender] = loanIndex.add(1);

      // Emit loan creation event
      emit Loan__LoanCreated(msg.sender, lsa, loanAmount, collateralAmount, block.timestamp);
    }

    // Flash loan execution flow
    {
      address[] memory assets = new address[](1);
      assets[0] = i_debtAsset;

      uint256[] memory amounts = new uint256[](1);
      amounts[0] = loanAmount;

      uint256[] memory modes = new uint256[](1);
      modes[0] = 0; // don't open any debt, just revert if funds can't be transferred from the receiver

      bytes memory params = abi.encode(lsa, collateralAmount);

      ILendingPool(i_AAVE_V3_POOL).flashLoan(
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
  ) external override returns (bool) {
    require(msg.sender == i_AAVE_V3_POOL, 'Loan: caller not Aave pool');
    require(initiator == address(this), 'Loan: invalid initiator');

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

    (address lsa, uint256 collateralAmount) = abi.decode(params, (address, uint256));

    // Retrieve loan data from storage
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];
    uint256 totalSwapAmount = loan.depositAmount.add(flashLoanAmount);

    uint256 wbtcReceived = SwapLogic.executeSwap(
      s_swapAdapter,
      s_zQuoter,
      i_debtAsset, // tokenIn
      i_collateralAsset, // tokenOut
      totalSwapAmount, // amountIn
      collateralAmount,
      MAX_SLIPPAGE_BPS,
      BASIS_POINTS
    );

    require(wbtcReceived >= collateralAmount, 'Loan: insufficient cbBTC received');

    uint256 borrowAmount = flashLoanAmount.add(flashLoanPremium);

    LSALogic.approveCreditDelegation(
      lsa,
      i_AAVE_V2_POOL,
      i_debtAsset,
      borrowAmount,
      address(this) // Protocol is the delegatee
    );

    AaveV2InteractionLogic.depositCollateral(i_AAVE_V2_POOL, i_collateralAsset, wbtcReceived, lsa);

    AaveV2InteractionLogic.borrowDebt(i_AAVE_V2_POOL, i_debtAsset, borrowAmount, lsa);

    IERC20(i_debtAsset).safeApprove(i_AAVE_V3_POOL, borrowAmount);

    return true;
  }

  // ============ View Functions ============

  /**
   * @notice Retrieves loan data for a specific LSA
   * @param lsa The LSA address
   * @return Loan data struct
   */
  function getLoanByLSA(address lsa) external view override returns (DataTypes.LoanData memory) {
    require(s_loansByLSA[lsa].borrower != address(0), 'Loan: loan does not exist');
    return s_loansByLSA[lsa];
  }

  /**
   * @notice Gets total number of loans created by a user
   * @param user The user address
   * @return Total loan count
   */
  function getUserLoanCount(address user) external view override returns (uint256) {
    return s_userLoanCount[user];
  }

  /**
   * @notice Gets LSA address for user's Nth loan
   * @param user The user address
   * @param index Loan index (0-based)
   * @return LSA address
   */
  function getUserLoanAtIndex(
    address user,
    uint256 index
  ) external view override returns (address) {
    require(index < s_userLoanCount[user], 'Loan: index out of bounds');
    return s_userLoanAtIndex[user][index];
  }

  /**
   * @notice Retrieves all loans for a specific user
   * @param user The user address
   * @return Array of loan data structs
   */
  function getUserAllLoans(
    address user
  ) external view override returns (DataTypes.LoanData[] memory) {
    uint256 count = s_userLoanCount[user];
    DataTypes.LoanData[] memory loans = new DataTypes.LoanData[](count);

    for (uint256 i = 0; i < count; i++) {
      address lsa = s_userLoanAtIndex[user][i];
      loans[i] = s_loansByLSA[lsa];
    }

    return loans;
  }

  /**
   * @notice Gets the collateral asset address
   * @return cbBTC address
   */
  function getCollateralAsset() external view override returns (address) {
    return i_collateralAsset;
  }

  /**
   * @notice Gets the debt asset address
   * @return USDC address
   */
  function getDebtAsset() external view override returns (address) {
    return i_debtAsset;
  }

  /**
   * @notice Calculates strike price for options based on loan parameters
   * @dev Formula: strike_price = btc_in_usd * loan_amount/(loan_amount + deposit) * 1.1
   * @param loanAmount The loan amount in USDC (6 decimals)
   * @param deposit The deposit amount in USDC (6 decimals)
   * @return strikePrice The calculated strike price in USD (8 decimals)
   */
  function calculateStrikePrice(
    uint256 loanAmount,
    uint256 deposit
  ) external view override returns (uint256 strikePrice) {
    require(loanAmount > 0, 'Loan: invalid loan amount');
    require(deposit > 0, 'Loan: invalid deposit');

    IPriceOracleGetter oracle = IPriceOracleGetter(
      ILendingPoolAddressesProvider(i_AAVE_ADDRESSES_PROVIDER).getPriceOracle()
    );

    uint256 btcPriceUSD = oracle.getAssetPrice(i_collateralAsset);
    require(btcPriceUSD > 0, 'Loan: invalid BTC price');

    uint256 totalAmount = loanAmount.add(deposit);

    strikePrice = btcPriceUSD.mul(loanAmount).div(totalAmount).mul(110).div(100);

    return strikePrice;
  }

  /**
   * @notice Allows borrower to repay their loan
   * @param lsa The Loan Specific Address
   * @param amount Amount of USDC to repay
   * @return finalAmountRepaid The amount repaid
   * @return nextDueTimestamp The next due timestamp
   */
  function repay(
    address lsa,
    uint256 amount
  ) external nonReentrant returns (uint256 finalAmountRepaid, uint256 nextDueTimestamp) {
    require(lsa != address(0), 'Loan: WRONG LSA ADDRESS');
    require(amount > 0, 'Loan: invalid withdrawal amount');
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    require(msg.sender == loan.borrower, 'Loan: caller is not borrower');
    require(loan.borrower != address(0), 'Loan: loan does not exist');
    require(loan.status == DataTypes.LoanStatus.Active, 'Loan: loan is not active');

    // Cap the requested amount to outstanding principal so we never custody more than needed
    uint256 maxRepayableAmt = _min(amount, loan.loanAmount);

    // Pull only what might be needed from the borrower
    IERC20(i_debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

    // Approve Aave V2 pool (the spender) to pull from THIS contract
    IERC20(i_debtAsset).safeApprove(i_AAVE_V2_POOL, 0);
    IERC20(i_debtAsset).safeApprove(i_AAVE_V2_POOL, maxRepayableAmt);

    // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
    (finalAmountRepaid, nextDueTimestamp) = RepayLogic.executeLoanRepayment(
      loan,
      i_AAVE_V2_POOL,
      i_debtAsset,
      lsa,
      maxRepayableAmt
    );

    // Refund any unspent amount to the payer
    if (finalAmountRepaid < maxRepayableAmt) {
      IERC20(i_debtAsset).safeTransfer(msg.sender, maxRepayableAmt - finalAmountRepaid);
    }

    emit Loan__LoanRepaid(lsa, finalAmountRepaid, nextDueTimestamp);
    return (finalAmountRepaid, nextDueTimestamp);
  }

  // ============ Withdrawal Function ============

  /**
   * @notice Allows borrower to withdraw collateral from their LSA
   * @param lsa The Loan Specific Address
   * @param amount Amount of cbBTC to withdraw
   * @return amountWithdrawn Actual amount withdrawn
   */
  function withdrawCollateral(
    address lsa,
    uint256 amount
  ) external override nonReentrant returns (uint256 amountWithdrawn) {
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    require(loan.borrower != address(0), 'Loan: loan does not exist');
    require(msg.sender == loan.borrower, 'Loan: caller is not borrower');
    require(loan.status == DataTypes.LoanStatus.Active, 'Loan: loan is not active');
    require(amount > 0, 'Loan: invalid withdrawal amount');

    // Check locked amount in Escrow
    uint256 lockedAmount = IEscrow(s_escrow).getLockedAmount(lsa);
    require(lockedAmount > 0, 'Loan: no collateral in escrow');
    require(amount <= lockedAmount, 'Loan: insufficient locked collateral');

    amountWithdrawn = WithdrawalLogic.withdrawCollateral(
      lsa,
      i_AAVE_V2_POOL,
      s_escrow,
      i_collateralAsset,
      amount,
      msg.sender // Send cbBTC to borrower
    );

    emit Loan__CollateralWithdrawn(lsa, msg.sender, amountWithdrawn, block.timestamp);

    return amountWithdrawn;
  }

  // ============ Admin Functions ============

  /**
   * @notice Updates the maximum loan amount
   * @param newMaxLoanAmount New maximum loan amount (6 decimals)
   */
  function setMaxLoanAmount(uint256 newMaxLoanAmount) external override onlyOwner {
    require(newMaxLoanAmount > 0, 'Loan: invalid max loan amount');
    uint256 oldAmount = s_maxLoanAmount;
    s_maxLoanAmount = newMaxLoanAmount;
    emit Loan__MaxLoanAmountUpdated(oldAmount, newMaxLoanAmount);
  }

  /**
   * @notice Updates the loan vault factory address
   * @param newFactory New factory address
   */
  function setLoanVaultFactory(address newFactory) external override onlyOwner {
    require(newFactory != address(0), 'Loan: invalid factory');
    address oldFactory = s_loanVaultFactory;
    s_loanVaultFactory = newFactory;
    emit Loan__LoanVaultFactoryUpdated(oldFactory, newFactory);
  }

  /**
   * @notice Updates the escrow contract address
   * @param newEscrow New escrow address
   */
  function setEscrow(address newEscrow) external override onlyOwner {
    require(newEscrow != address(0), 'Loan: invalid escrow');
    address oldEscrow = s_escrow;
    s_escrow = newEscrow;
    emit Loan__EscrowUpdated(oldEscrow, newEscrow);
  }

  /**
   * @notice Updates the swap adapter contract address
   * @param newSwapAdapter New swap adapter address
   */
  function setSwapAdapter(address newSwapAdapter) external override onlyOwner {
    require(newSwapAdapter != address(0), 'Loan: invalid swap adapter');
    address oldSwapAdapter = s_swapAdapter;
    s_swapAdapter = newSwapAdapter;
    emit Loan__SwapAdapterUpdated(oldSwapAdapter, newSwapAdapter);
  }

  /**
   * @notice Updates the zQuoter contract address
   * @param newZQuoter New zQuoter address
   */
  function setZQuoter(address newZQuoter) external override onlyOwner {
    require(newZQuoter != address(0), 'Loan: invalid zQuoter');
    address oldZQuoter = s_zQuoter;
    s_zQuoter = newZQuoter;
    emit Loan__ZQuoterUpdated(oldZQuoter, newZQuoter);
  }

  /**
   * @notice Updates loan status
   * @dev Used by repayment and liquidation flows
   * @param lsa The LSA address
   * @param newStatus The new loan status
   */
  function updateLoanStatus(
    address lsa,
    DataTypes.LoanStatus newStatus
  ) external override onlyOwner {
    require(s_loansByLSA[lsa].borrower != address(0), 'Loan: loan does not exist');
    DataTypes.LoanStatus oldStatus = s_loansByLSA[lsa].status;
    s_loansByLSA[lsa].status = newStatus;
    emit Loan__LoanStatusUpdated(lsa, oldStatus, newStatus);
  }

  /**
   * @notice Update the LoanData for an LSA.
   * @param _data The update LoanData
   * @param _lsa The Loan specific address
   */
  function updateLoanData(bytes calldata _data, address _lsa) external override onlyOwner {
    DataTypes.LoanData memory data = abi.decode(_data, (DataTypes.LoanData));
    s_loansByLSA[_lsa] = data;

    emit Loan__LoanDataUpdated(_lsa, block.timestamp);
  }

  /**
   * @notice Returns the minimum of two uint256 values
   * @param a The first value
   * @param b The second value
   * @return The minimum of the two values
   */
  function _min(uint256 a, uint256 b) private pure returns (uint256) {
    return a < b ? a : b;
  }
}
