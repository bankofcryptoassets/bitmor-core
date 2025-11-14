// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from '../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../dependencies/openzeppelin/SafeERC20.sol';
import {Ownable} from '../dependencies/openzeppelin/Ownable.sol';
import {ReentrancyGuard} from '../dependencies/openzeppelin/ReentrancyGuard.sol';
import {LoanStorage} from './LoanStorage.sol';
import {LoanLogic, LoanMath} from '../libraries/logic/LoanLogic.sol';
import {ILendingPool} from '../interfaces/ILendingPool.sol';
import {IPriceOracleGetter} from '../interfaces/IPriceOracleGetter.sol';
import {ILoanVaultFactory} from '../interfaces/ILoanVaultFactory.sol';
import {SwapLogic} from '../libraries/logic/SwapLogic.sol';
import {AaveV2InteractionLogic} from '../libraries/logic/AaveV2InteractionLogic.sol';
import {LSALogic} from '../libraries/logic/LSALogic.sol';
import {ILoan} from '../interfaces/ILoan.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';

/**
 * @title Loan
 * @notice Main contract for Bitmor Protocol loan creation and management
 * @dev Implements ILoan interface with full loan lifecycle management
 */
contract Loan is LoanStorage, ILoan, Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // ============ Constructor ============

  /**
   * @notice Initializes the Loan contract with protocol addresses and configuration
   * @param _aaveV3Pool Aave V3 pool address for flash loans
   * @param _bitmorPool Bitmor Lending Pool
   * @param _oracle Price Oracle
   * @param _collateralAsset cbBTC address
   * @param _debtAsset USDC address
   * @param _swapAdapter SwapAdapter contract address for token swaps
   * @param _zQuoter zQuoter contract address (address(0) for Uniswap V4 on Base Sepolia)
   * @param _maxLoanAmount Maximum loan amount allowed (6 decimals for USDC)
   */
  constructor(
    address _aaveV3Pool,
    address _bitmorPool,
    address _oracle,
    address _collateralAsset,
    address _debtAsset,
    address _swapAdapter,
    address _zQuoter,
    uint256 _maxLoanAmount
  )
    LoanStorage(_aaveV3Pool, _bitmorPool, _oracle, _collateralAsset, _debtAsset)
    Ownable(msg.sender)
  {
    require(_swapAdapter != address(0), 'Loan: invalid swap adapter');
    require(_maxLoanAmount > 0, 'Loan: invalid max loan amount');

    s_swapAdapter = _swapAdapter;
    s_zQuoter = _zQuoter;
    s_maxLoanAmount = _maxLoanAmount;
  }

  modifier checkZeroAmount(uint256 amt) {
    _checkZeroAmount(amt);
    _;
  }

  modifier checkZeroAddress(address _add) {
    _checkZeroAddress(_add);
    _;
  }

  modifier checkIfLoanExists(address _lsa) {
    _checkIfLoanExists(_lsa);
    _;
  }

  // ============ Main Loan Creation ============

  /// @inheritdoc ILoan
  function initializeLoan(
    uint256 depositAmount,
    uint256 premiumAmount,
    uint256 collateralAmount,
    uint256 duration,
    uint256 insuranceID
  ) external override nonReentrant returns (address lsa) {
    require(depositAmount > 0, 'Loan: invalid deposit amount');
    require(collateralAmount > 0, 'Loan: invalid collateral amount');
    require(duration > 0, 'Loan: invalid duration');

    // Transfer deposit from user to contract
    IERC20(i_debtAsset).safeTransferFrom(msg.sender, address(this), depositAmount);

    // Transfer premium amount to premium collector
    if (premiumAmount > 0) {
      IERC20(i_debtAsset).safeTransferFrom(msg.sender, s_premiumCollector, premiumAmount);
    }

    uint256 loanAmount;
    // Calculate loan details and store data
    {
      uint256 monthlyPayment;

      (loanAmount, monthlyPayment, ) = LoanLogic.calculateLoanAmountAndMonthlyPayment(
        i_BITMOR_POOL,
        i_ORACLE,
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
      uint256 firstPaymentDue = block.timestamp + LOAN_REPAYMENT_INTERVAL;

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
        lastDueTimestamp: 0,
        status: DataTypes.LoanStatus.Active
      });

      // Update user loan indexing for multi-loan support
      uint256 loanIndex = s_userLoanCount[msg.sender];
      s_userLoanAtIndex[msg.sender][loanIndex] = lsa;
      s_userLoanCount[msg.sender] = loanIndex + 1;
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

    // Emit loan creation event
    emit Loan__LoanCreated(msg.sender, lsa, loanAmount, collateralAmount, block.timestamp);
    return lsa;
  }

  // ============ Flash Loan Callback ============

  /// @inheritdoc ILoan
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    if (msg.sender != i_AAVE_V3_POOL) revert Loan__CallerIsNotAAVEPool();

    if (initiator != address(this)) revert Loan__WrongFlashLoanInitiator();

    // Flash loan execution logic will be implemented here
    // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

    (address lsa, uint256 collateralAmount) = abi.decode(params, (address, uint256));

    // Retrieve loan data from storage
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];
    uint256 totalSwapAmount = loan.depositAmount + flashLoanAmount;

    uint256 minimumAcceptable = SwapLogic.calculateMinBTCAmt(
      s_zQuoter,
      i_debtAsset, // tokenIn
      i_collateralAsset, // tokenOut
      totalSwapAmount, // amountIn
      collateralAmount,
      MAX_SLIPPAGE_BPS,
      BASIS_POINTS
    );

    // Approve SwapAdaptor to spend tokens
    IERC20(i_debtAsset).forceApprove(s_swapAdapter, totalSwapAmount);

    uint256 amountReceived = SwapLogic.executeSwap(
      s_swapAdapter,
      i_debtAsset,
      i_collateralAsset,
      totalSwapAmount,
      minimumAcceptable
    );

    if (amountReceived < minimumAcceptable) revert Loan__InsufficientCBBTCReceived();

    uint256 borrowAmount = flashLoanAmount + flashLoanPremium;

    LSALogic.approveCreditDelegation(
      lsa,
      i_BITMOR_POOL,
      i_debtAsset,
      borrowAmount,
      address(this) // Protocol is the delegatee
    );

    AaveV2InteractionLogic.depositCollateral(i_BITMOR_POOL, i_collateralAsset, amountReceived, lsa);

    AaveV2InteractionLogic.borrowDebt(i_BITMOR_POOL, i_debtAsset, borrowAmount, lsa);

    IERC20(i_debtAsset).forceApprove(i_AAVE_V3_POOL, borrowAmount);

    return true;
  }

  // ============ View Functions ============

  /// @inheritdoc ILoan
  function getLoanByLSA(
    address lsa
  )
    external
    view
    override
    checkZeroAddress(lsa)
    checkIfLoanExists(lsa)
    returns (DataTypes.LoanData memory)
  {
    return s_loansByLSA[lsa];
  }

  /// @inheritdoc ILoan
  function getUserLoanCount(
    address user
  ) external view override checkZeroAddress(user) returns (uint256) {
    return s_userLoanCount[user];
  }

  /// @inheritdoc ILoan
  function getUserLoanAtIndex(
    address user,
    uint256 index
  ) external view override checkZeroAddress(user) returns (address) {
    if (index >= s_userLoanCount[user]) revert Loan__IndexOutOfBound();
    return s_userLoanAtIndex[user][index];
  }

  /// @inheritdoc ILoan
  function getUserAllLoans(
    address user
  ) external view override checkZeroAddress(user) returns (DataTypes.LoanData[] memory) {
    uint256 count = s_userLoanCount[user];
    DataTypes.LoanData[] memory loans = new DataTypes.LoanData[](count);

    for (uint256 i = 0; i < count; i++) {
      address lsa = s_userLoanAtIndex[user][i];
      loans[i] = s_loansByLSA[lsa];
    }

    return loans;
  }

  /// @inheritdoc ILoan
  function getCollateralAsset() external view override returns (address) {
    return i_collateralAsset;
  }

  /// @inheritdoc ILoan
  function getDebtAsset() external view override returns (address) {
    return i_debtAsset;
  }

  /// @inheritdoc ILoan
  function calculateStrikePrice(
    uint256 loanAmount,
    uint256 deposit
  )
    external
    view
    override
    checkZeroAmount(loanAmount)
    checkZeroAmount(deposit)
    returns (uint256 strikePrice)
  {
    IPriceOracleGetter oracle = IPriceOracleGetter(i_ORACLE);

    uint256 btcPriceUSD = oracle.getAssetPrice(i_collateralAsset);
    if (btcPriceUSD == 0) revert Loan__InvalidAssetPrice();

    uint256 totalAmount = loanAmount + deposit;

    strikePrice = (btcPriceUSD * loanAmount * 110) / (totalAmount * 100);

    return strikePrice;
  }

  /// @inheritdoc ILoan
  function repay(
    address lsa,
    uint256 amount
  )
    external
    override
    nonReentrant
    checkZeroAddress(lsa)
    checkZeroAmount(amount)
    checkIfLoanExists(lsa)
    returns (uint256 finalAmountRepaid, uint256 nextDueTimestamp)
  {
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    if (msg.sender != loan.borrower) revert Loan__CallerIsNotBorrower();
    if (loan.status != DataTypes.LoanStatus.Active) revert Loan__LoanIsNotActive(loan.status);

    // Cap the requested amount to outstanding principal so we never custody more than needed
    uint256 maxRepayableAmt = LoanMath.min(amount, loan.loanAmount);

    // Pull only what might be needed from the borrower
    IERC20(i_debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

    // Approve Aave V2 pool (the spender) to pull from THIS contract
    IERC20(i_debtAsset).forceApprove(i_BITMOR_POOL, maxRepayableAmt);

    // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
    (finalAmountRepaid, nextDueTimestamp) = AaveV2InteractionLogic.executeLoanRepayment(
      loan,
      i_BITMOR_POOL,
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

  /// @inheritdoc ILoan
  function closeLoan(
    address lsa,
    uint256 amount
  )
    external
    override
    nonReentrant
    checkZeroAddress(lsa)
    checkZeroAmount(amount)
    checkIfLoanExists(lsa)
    returns (uint256 finalAmountRepaid, uint256 amountWithdrawn)
  {
    DataTypes.LoanData storage loan = s_loansByLSA[lsa];

    if (msg.sender != loan.borrower) revert Loan__CallerIsNotBorrower();
    if (loan.status != DataTypes.LoanStatus.Active) revert Loan__LoanIsNotActive(loan.status);

    uint256 totalDebtAmt = AaveV2InteractionLogic.getUserCurrentDebt(i_BITMOR_POOL, lsa);

    if (amount < totalDebtAmt) {
      revert Loan__InsufficientAmountSuppliedForClosure(totalDebtAmt, amount);
    }

    IERC20(i_debtAsset).safeTransferFrom(msg.sender, address(this), totalDebtAmt);

    IERC20(i_debtAsset).forceApprove(i_BITMOR_POOL, totalDebtAmt);
    (finalAmountRepaid, amountWithdrawn) = AaveV2InteractionLogic.closeLoan(
      i_BITMOR_POOL,
      lsa,
      i_debtAsset,
      i_collateralAsset,
      msg.sender,
      totalDebtAmt
    );

    emit Loan__ClosedLoan(lsa, finalAmountRepaid, amountWithdrawn);

    return (finalAmountRepaid, amountWithdrawn);
  }

  // ============ Admin Functions ============

  /// @inheritdoc ILoan
  function setMaxLoanAmount(
    uint256 newMaxLoanAmount
  ) external override checkZeroAmount(newMaxLoanAmount) onlyOwner {
    s_maxLoanAmount = newMaxLoanAmount;
    emit Loan__MaxLoanAmountUpdated(newMaxLoanAmount);
  }

  /// @inheritdoc ILoan
  function setLoanVaultFactory(
    address newFactory
  ) external override checkZeroAddress(newFactory) onlyOwner {
    s_loanVaultFactory = newFactory;
    emit Loan__LoanVaultFactoryUpdated(newFactory);
  }

  /// @inheritdoc ILoan
  function setEscrow(address newEscrow) external override checkZeroAddress(newEscrow) onlyOwner {
    s_escrow = newEscrow;
    emit Loan__EscrowUpdated(newEscrow);
  }

  /// @inheritdoc ILoan
  function setSwapAdapter(
    address newSwapAdapter
  ) external override checkZeroAddress(newSwapAdapter) onlyOwner {
    s_swapAdapter = newSwapAdapter;
    emit Loan__SwapAdapterUpdated(newSwapAdapter);
  }

  /// @inheritdoc ILoan
  function setZQuoter(address newZQuoter) external override checkZeroAddress(newZQuoter) onlyOwner {
    s_zQuoter = newZQuoter;
    emit Loan__ZQuoterUpdated(newZQuoter);
  }

  /// @inheritdoc ILoan
  function updateLoanStatus(
    address lsa,
    DataTypes.LoanStatus newStatus
  ) external override checkIfLoanExists(lsa) onlyOwner {
    DataTypes.LoanStatus oldStatus = s_loansByLSA[lsa].status;
    s_loansByLSA[lsa].status = newStatus;
    emit Loan__LoanStatusUpdated(lsa, oldStatus, newStatus);
  }

  /// @inheritdoc ILoan
  function updateLoanData(
    bytes calldata _data,
    address _lsa
  ) external override checkZeroAddress(_lsa) onlyOwner {
    DataTypes.LoanData memory data = abi.decode(_data, (DataTypes.LoanData));
    s_loansByLSA[_lsa] = data;

    emit Loan__LoanDataUpdated(_lsa, _data);
  }

  function getLoanDetails(
    uint256 collateralAmount,
    uint256 duration
  ) external view returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired) {
    (loanAmount, monthlyPayment, minDepositRequired) = LoanLogic.calculateLoanDetails(
      i_BITMOR_POOL,
      i_ORACLE,
      i_collateralAsset,
      i_debtAsset,
      s_maxLoanAmount,
      collateralAmount,
      duration
    );
  }

  /// @inheritdoc ILoan
  function setPremiumCollector(
    address newPremiumCollector
  ) external override checkZeroAddress(newPremiumCollector) onlyOwner {
    s_premiumCollector = newPremiumCollector;
    emit Loan__PremiumCollectorUpdated(s_premiumCollector);
  }

  function _checkZeroAmount(uint256 amt) internal view {
    if (amt == 0) {
      revert Loan__ZeroAmount();
    }
  }

  function _checkZeroAddress(address _add) internal view {
    if (_add == address(0)) {
      revert Loan__ZeroAddress();
    }
  }

  function _checkIfLoanExists(address _lsa) internal view {
    if (s_loansByLSA[_lsa].borrower == address(0)) {
      revert Loan__LoanDoesNotExist();
    }
  }
}
