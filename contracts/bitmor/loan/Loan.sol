// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {Ownable} from '../dependencies/openzeppelin/Ownable.sol';
import {ReentrancyGuard} from '../dependencies/openzeppelin/ReentrancyGuard.sol';
import {LoanStorage} from './LoanStorage.sol';
import {LoanLogic, LoanMath} from '../libraries/logic/LoanLogic.sol';
import {IPriceOracleGetter} from '../interfaces/IPriceOracleGetter.sol';
import {ILoan} from '../interfaces/ILoan.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';
import {RepayLogic} from '../libraries/logic/RepayLogic.sol';
import {CloseLoanLogic} from '../libraries/logic/CloseLoanLogic.sol';
import {FlashLoanLogic} from '../libraries/logic/FlashLoanLogic.sol';
import {Errors} from '../libraries/helpers/Errors.sol';
import {IFlashLoanSimpleReceiver} from '../interfaces/IFlashLoanSimpleReceiver.sol';
import {IPool, IPoolAddressesProvider} from '../interfaces/IPool.sol';

/**
 * @title Loan
 * @notice Main contract for Bitmor Protocol loan creation and management
 * @dev Implements ILoan interface with full loan lifecycle management
 */
contract Loan is LoanStorage, ILoan, Ownable, ReentrancyGuard, IFlashLoanSimpleReceiver {
  // ============ Constructor ============

  /**
   * @notice Initializes the Loan contract with protocol addresses and configuration
   * @param _aaveV3Pool Aave V3 pool address for flash loans
   * @param _aaveAddressesProvider Addresses Provider for flash loan operations
   * @param _bitmorPool Bitmor Lending Pool
   * @param _oracle Price Oracle
   * @param _collateralAsset cbBTC address
   * @param _debtAsset USDC address
   * @param _swapAdapter SwapAdapter contract address for token swaps
   * @param _zQuoter zQuoter contract address (address(0) for Uniswap V4 on Base Sepolia)
   * @param _preClosureFeeBps Loan pre-closure fee (in bps)
   */
  constructor(
    address _aaveV3Pool,
    address _aaveAddressesProvider,
    address _bitmorPool,
    address _oracle,
    address _collateralAsset,
    address _debtAsset,
    address _swapAdapter,
    address _zQuoter,
    address _premiumCollector,
    uint256 _preClosureFeeBps
  )
    LoanStorage(
      _aaveV3Pool,
      _aaveAddressesProvider,
      _bitmorPool,
      _oracle,
      _collateralAsset,
      _debtAsset
    )
    Ownable(msg.sender)
  {
    if (_swapAdapter == address(0) || _premiumCollector == address(0)) revert Errors.ZeroAddress();

    s_swapAdapter = _swapAdapter;
    s_zQuoter = _zQuoter;
    s_premiumCollector = _premiumCollector;
    s_preClosureFeeBps = _preClosureFeeBps;
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
    uint256 insuranceID,
    address onBehalfOf
  ) external override nonReentrant returns (address lsa) {
    DataTypes.InitializeLoanContext memory ctx = DataTypes.InitializeLoanContext({
      bitmorPool: i_BITMOR_POOL,
      oracle: i_ORACLE,
      collateralAsset: i_COLLATERAL_ASSET,
      debtAsset: i_DEBT_ASSET,
      aavePool: i_AAVE_V3_POOL,
      loanVaultFactory: s_loanVaultFactory,
      premiumCollector: s_premiumCollector,
      maxCollateralAmt: MAX_COLLATERAL_AMOUNT,
      loanRepaymentInterval: LOAN_REPAYMENT_INTERVAL
    });

    lsa = LoanLogic.executeInitializeLoan(
      ctx,
      DataTypes.ExecuteInitializeLoanParams(
        onBehalfOf,
        depositAmount,
        premiumAmount,
        collateralAmount,
        duration,
        insuranceID
      ),
      s_loansByLSA,
      s_userLoanCount,
      s_userLoanAtIndex
    );
  }

  /// @inheritdoc ILoan
  function repay(
    address lsa,
    uint256 amount
  ) external override nonReentrant returns (uint256 finalAmountRepaid) {
    finalAmountRepaid = RepayLogic.executeRepay(
      i_BITMOR_POOL,
      i_DEBT_ASSET,
      i_COLLATERAL_ASSET,
      DataTypes.ExecuteRepayParams(lsa, amount),
      s_loansByLSA
    );
  }

  // ============ Close Loan Function  ============

  /// @inheritdoc ILoan
  function closeLoan(address lsa, bool withdrawInCollateralAsset) external override nonReentrant {
    DataTypes.ExecuteCloseLoanContext memory ctx = DataTypes.ExecuteCloseLoanContext(
      i_BITMOR_POOL,
      i_AAVE_V3_POOL,
      i_ORACLE,
      i_DEBT_ASSET,
      i_COLLATERAL_ASSET,
      s_preClosureFeeBps,
      MAX_SLIPPAGE_BPS
    );
    DataTypes.ExecuteCloseLoanParams memory params = DataTypes.ExecuteCloseLoanParams(
      lsa,
      withdrawInCollateralAsset
    );
    CloseLoanLogic.executeCloseLoan(ctx, params, s_loansByLSA);
  }

  // ============ Flash Loan Callback ============

  /// @inheritdoc IFlashLoanSimpleReceiver
  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    (bool initializingLoan, bytes memory flData) = abi.decode(params, (bool, bytes));

    DataTypes.ExecuteFLOperationContext memory ctx = DataTypes.ExecuteFLOperationContext(
      i_AAVE_V3_POOL,
      i_BITMOR_POOL,
      s_zQuoter,
      i_DEBT_ASSET,
      i_COLLATERAL_ASSET,
      s_swapAdapter,
      s_premiumCollector,
      MAX_SLIPPAGE_BPS
    );

    DataTypes.ExecuteFLOperationParams memory flOpParams = DataTypes.ExecuteFLOperationParams(
      asset,
      amount,
      premium,
      initiator,
      flData
    );

    if (initializingLoan) {
      FlashLoanLogic.executeFLOperationInitiailizingLoan(ctx, flOpParams, s_loansByLSA);
    } else {
      FlashLoanLogic.executeFLOperationCloseLoan(ctx, flOpParams, s_loansByLSA);
    }

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
    if (index >= s_userLoanCount[user]) revert Errors.IndexOutOfBounds();
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
    return i_COLLATERAL_ASSET;
  }

  /// @inheritdoc ILoan
  function getDebtAsset() external view override returns (address) {
    return i_DEBT_ASSET;
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

    uint256 btcPriceUSD = oracle.getAssetPrice(i_COLLATERAL_ASSET);
    if (btcPriceUSD == 0) revert Errors.InvalidAssetPrice();

    strikePrice = LoanMath.calculateStrikePrice(btcPriceUSD, loanAmount, deposit);
  }

  /// @inheritdoc ILoan
  function getLoanDetails(
    uint256 collateralAmount,
    uint256 duration
  ) external view returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired) {
    (loanAmount, monthlyPayment, minDepositRequired) = LoanLogic.calculateLoanDetails(
      i_BITMOR_POOL,
      i_ORACLE,
      i_COLLATERAL_ASSET,
      i_DEBT_ASSET,
      collateralAmount,
      duration
    );
  }

  /// @inheritdoc ILoan
  function getGracePeriod() external view override returns (uint256) {
    return s_gracePeriod;
  }

  /// @inheritdoc ILoan
  function getPremiumCollector() external view override returns (address) {
    return s_premiumCollector;
  }

  /// @inheritdoc ILoan
  function getRepaymentInterval() external view returns (uint256) {
    return LOAN_REPAYMENT_INTERVAL;
  }

  /// @inheritdoc IFlashLoanSimpleReceiver
  function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {
    return IPoolAddressesProvider(i_AAVE_ADDRESSES_PROVIDER);
  }

  /// @inheritdoc IFlashLoanSimpleReceiver
  function POOL() external view override returns (IPool) {
    return IPool(i_AAVE_V3_POOL);
  }

  /// @inheritdoc ILoan
  function getPreClosureFee() external view override returns (uint256) {
    return s_preClosureFeeBps;
  }

  // ============ Admin Functions ============

  /// @inheritdoc ILoan
  function setLoanVaultFactory(
    address newFactory
  ) external override checkZeroAddress(newFactory) onlyOwner {
    s_loanVaultFactory = newFactory;
    emit Loan__LoanVaultFactoryUpdated(newFactory);
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

  /// @inheritdoc ILoan
  function setPremiumCollector(
    address newPremiumCollector
  ) external override checkZeroAddress(newPremiumCollector) onlyOwner {
    s_premiumCollector = newPremiumCollector;
    emit Loan__PremiumCollectorUpdated(s_premiumCollector);
  }

  /// @inheritdoc ILoan
  function setGracePeriod(uint256 gracePeriod) external override onlyOwner {
    s_gracePeriod = gracePeriod;
    emit Loan__GracePeriodUpdated(gracePeriod);
  }

  /// @inheritdoc ILoan
  function setPreClosureFee(uint256 newFee) external override onlyOwner {
    s_preClosureFeeBps = newFee;
    emit Loan__PreClosureFeeUpdated(newFee);
  }

  // ============ Internal Functions ============

  function _checkZeroAmount(uint256 amt) internal pure {
    if (amt == 0) {
      revert Errors.ZeroAmount();
    }
  }

  function _checkZeroAddress(address _add) internal pure {
    if (_add == address(0)) {
      revert Errors.ZeroAddress();
    }
  }

  function _checkIfLoanExists(address _lsa) internal view {
    if (s_loansByLSA[_lsa].borrower == address(0)) {
      revert Errors.LoanDoesNotExists();
    }
  }
}
