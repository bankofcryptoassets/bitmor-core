// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {LoanLogic, LoanMath} from "../libraries/logic/LoanLogic.sol";
import {LSALogic} from "../libraries/logic/LSALogic.sol";
import {IPriceOracleGetter} from "../interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {RepayLogic} from "../libraries/logic/RepayLogic.sol";
import {CloseLoanLogic} from "../libraries/logic/CloseLoanLogic.sol";
import {FlashLoanLogic} from "../libraries/logic/FlashLoanLogic.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import {ILoan} from "../interfaces/ILoan.sol";
import {IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimpleReceiver.sol";
import {IPool, IPoolAddressesProvider} from "../interfaces/IPool.sol";
import {IBitmorAddressesProvider} from "../interfaces/IBitmorAddressesProvider.sol";

import {LoanStorage} from "./LoanStorage.sol";

/**
 * @title Loan
 * @author Bitmor Protocol
 * @notice Main contract for Bitmor Protocol loan creation and management
 * @dev Implements ILoan interface with full loan lifecycle management.
 *
 * ## Overview
 * This contract is the central entry point for the Bitmor lending protocol. It enables users
 * to take BTC-collateralized loans using flash loans from Aave V3 for capital efficiency.
 *
 * ## Loan Flow
 * 1. User calls `initializeLoan()` with deposit, collateral amount, and duration
 * 2. Contract creates a Loan Specific Address (LSA) via `LoanVaultFactory`
 * 3. Flash loan is taken from Aave V3 for the loan amount
 * 4. USDC is swapped to cbBTC via Uniswap V4
 * 5. bvBTC collateral is deposited to Bitmor Lending Pool
 * 6. User repays monthly via `repay()` or closes early via `closeLoan()`
 *
 * @custom:security Uses reentrancy guards, access control, and pausability for secure operations
 * @custom:security Flash loan callback validates caller is Aave V3 pool and initiator is this contract
 */
contract Loan is
    Initializable,
    UUPSUpgradeable,
    LoanStorage,
    ILoan,
    ReentrancyGuardTransient,
    IFlashLoanSimpleReceiver,
    AccessManagedUpgradeable,
    PausableUpgradeable
{
    using LSALogic for address;
    using FlashLoanLogic for DataTypes.ExecuteFLOperationContext;
    using CloseLoanLogic for DataTypes.ExecuteCloseLoanContext;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Loan contract with protocol addresses and configuration
     * @param _manager AccessManager contract address for role-based access control
     * @param _aaveV3Pool Aave V3 pool address for flash loans
     * @param _aaveAddressesProvider Addresses Provider for flash loan operations
     * @param _bitmorPool Bitmor Lending Pool
     * @param _oracle Price Oracle
     * @param _collateralAsset `bvBTC` address
     * @param _debtAsset USDC address
     * @param _btc Wrapped BTC address
     * @param _preClosureFeeBps Loan pre-closure fee (in bps)
     * @param _gracePeriod Grace period for monthly payment in seconds
     */
    function initialize(
        address _manager,
        address _aaveV3Pool,
        address _aaveAddressesProvider,
        address _bitmorPool,
        address _oracle,
        address _collateralAsset,
        address _debtAsset,
        address _btc,
        uint256 _preClosureFeeBps,
        uint256 _gracePeriod
    ) public initializer {
        __AccessManaged_init(_manager);

        __Pausable_init();

        LoanStorageData storage $ = _getLoanStorage();
        // Validate addresses (same checks as old constructor)
        if (_aaveV3Pool == address(0)) revert Errors.ZeroAddress();
        if (_aaveAddressesProvider == address(0)) revert Errors.ZeroAddress();
        if (_bitmorPool == address(0)) revert Errors.ZeroAddress();
        if (_oracle == address(0)) revert Errors.ZeroAddress();
        if (_collateralAsset == address(0)) revert Errors.ZeroAddress();
        if (_debtAsset == address(0)) revert Errors.ZeroAddress();
        if (_btc == address(0)) revert Errors.ZeroAddress();
        if (_preClosureFeeBps >= BASIS_POINT_SCALE) revert Errors.InvalidFee();
        if (_gracePeriod > MAX_GRACE_PERIOD) revert Errors.InvalidInputs();

        $.aaveV3Pool = _aaveV3Pool;
        $.aaveAddressesProvider = _aaveAddressesProvider;
        $.bitmorPool = _bitmorPool;
        $.oracle = _oracle;
        $.collateralAsset = _collateralAsset;
        $.debtAsset = _debtAsset;
        $.btc = _btc;
        $.preClosureFeeBps = _preClosureFeeBps;
        $.gracePeriod = _gracePeriod;
    }

    /**
     * @notice Reverts if `amt` is zero
     * @param amt The amount to validate
     */
    modifier checkZeroAmount(uint256 amt) {
        _checkZeroAmount(amt);
        _;
    }

    /**
     * @notice Reverts if `_add` is the zero address
     * @param _add The address to validate
     */
    modifier checkZeroAddress(address _add) {
        _checkZeroAddress(_add);
        _;
    }

    /**
     * @notice Reverts if no loan exists for the given LSA
     * @param _lsa The Loan Specific Address to check
     */
    modifier checkIfLoanExists(address _lsa) {
        _checkIfLoanExists(_lsa);
        _;
    }

    // ============ Main Loan Creation ============

    /**
     * @inheritdoc ILoan
     */
    function initializeLoan(
        uint256 depositAmount,
        uint256 premiumAmount,
        uint256 btcAmount,
        uint256 duration,
        bytes calldata data
    ) external whenNotPaused restricted nonReentrant returns (address lsa) {
        LoanStorageData storage $ = _getLoanStorage();

        DataTypes.InitializeLoanContext memory ctx = DataTypes.InitializeLoanContext({
            bitmorPool: $.bitmorPool,
            oracle: $.oracle,
            btc: $.btc,
            debtAsset: $.debtAsset,
            aavePool: $.aaveV3Pool,
            loanVaultFactory: getLoanVaultFactory(),
            premiumCollector: getPremiumCollector(),
            minBTCAmt: $.minBTCAmt,
            maxBTCAmt: $.maxBTCAmt,
            loanRepaymentInterval: LOAN_REPAYMENT_INTERVAL,
            minDepositBps: $.minDeposit,
            maxDuration: $.maxDuration
        });

        lsa = LoanLogic.executeInitializeLoan(
            LOAN_STORAGE_LOCATION,
            ctx,
            DataTypes.ExecuteInitializeLoanParams(
                msg.sender, depositAmount, premiumAmount, btcAmount, duration, INITIAL_INSURANCE_ID, data
            )
        );
    }

    /**
     * @inheritdoc ILoan
     */
    function repay(address lsa, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 finalAmountRepaid)
    {
        LoanStorageData storage $ = _getLoanStorage();
        finalAmountRepaid = RepayLogic.executeRepay(
            $.bitmorPool,
            $.debtAsset,
            $.collateralAsset,
            getAutoRepayer(),
            DataTypes.ExecuteRepayParams(lsa, amount, $.slippageSharesToAsset),
            $.loansByLSA
        );
    }

    // ============ Close Loan Function  ============

    /**
     * @inheritdoc ILoan
     */
    function closeLoan(address lsa, bool withdrawInBTC) external whenNotPaused nonReentrant {
        LoanStorageData storage $ = _getLoanStorage();
        DataTypes.ExecuteCloseLoanContext memory ctx = DataTypes.ExecuteCloseLoanContext(
            $.bitmorPool,
            $.aaveV3Pool,
            $.oracle,
            $.debtAsset,
            $.collateralAsset,
            $.btc,
            $.preClosureFeeBps,
            $.slippageSwap
        );
        DataTypes.ExecuteCloseLoanParams memory params = DataTypes.ExecuteCloseLoanParams(lsa, withdrawInBTC);
        ctx.executeCloseLoan(params, $.loansByLSA);
    }

    // ============ State Update Function  ============

    /**
     * @inheritdoc ILoan
     */
    function updateInsuranceId(address lsa, uint256 insuranceID)
        external
        whenNotPaused
        restricted
        checkIfLoanExists(lsa)
    {
        LoanLogic.updateInsuranceId(LOAN_STORAGE_LOCATION, lsa, insuranceID);
        emit Loan__InsuranceIDUpdated(lsa, insuranceID);
    }

    /**
     * @inheritdoc ILoan
     */
    function updateLoanDataForMicroLiquidation(address _lsa) external whenNotPaused restricted checkZeroAddress(_lsa) {
        uint256 newDuration = LoanLogic.updateLoanDataForMicroLiquidation(LOAN_STORAGE_LOCATION, _lsa);
        emit Loan__LoanDataForMicroLiquidationUpdated(_lsa, newDuration);
    }

    /// @inheritdoc ILoan
    function updateLoanForMicroLiquidationCompletion(address _lsa)
        external
        whenNotPaused
        restricted
        nonReentrant
        checkZeroAddress(_lsa)
        checkIfLoanExists(_lsa)
    {
        LoanLogic.updateLoanForMicroLiquidationCompletion(LOAN_STORAGE_LOCATION, _lsa);

        emit Loan__Completed(_lsa);
    }

    /**
     * @inheritdoc ILoan
     */
    function updateLoanDataForFullLiquidation(address _lsa)
        external
        whenNotPaused
        restricted
        nonReentrant
        checkZeroAddress(_lsa)
        checkIfLoanExists(_lsa)
    {
        LoanLogic.updateLoanDataForFullLiquidation(LOAN_STORAGE_LOCATION, _lsa);

        emit Loan__LoanDataForFullLiquidationUpdated(_lsa);
    }

    // ============ Flash Loan Callback ============

    /**
     * @inheritdoc IFlashLoanSimpleReceiver
     */
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        (bool initializingLoan, bytes memory flData) = abi.decode(params, (bool, bytes));

        LoanStorageData storage $ = _getLoanStorage();
        DataTypes.ExecuteFLOperationContext memory ctx = DataTypes.ExecuteFLOperationContext({
            aavePool: $.aaveV3Pool,
            bitmorPool: $.bitmorPool,
            swapper: getSwapper(),
            debtAsset: $.debtAsset,
            collateralAsset: $.collateralAsset,
            btc: $.btc,
            feeCollector: getPremiumCollector(),
            oracle: $.oracle,
            maxSlippage: $.slippageSwap
        });

        DataTypes.ExecuteFLOperationParams memory flOpParams = DataTypes.ExecuteFLOperationParams({
            asset: asset,
            amount: amount,
            premium: premium,
            initiator: initiator,
            params: flData,
            slippage_sharesToAsset: $.slippageSharesToAsset
        });

        if (initializingLoan) {
            ctx.executeFLOperationInitiailizingLoan(flOpParams, $.loansByLSA);
        } else {
            ctx.executeFLOperationCloseLoan(flOpParams, $.loansByLSA);
        }

        return true;
    }

    // ============ View Functions ============

    /**
     * @inheritdoc ILoan
     */
    function getLoanByLSA(address lsa)
        external
        view
        checkZeroAddress(lsa)
        checkIfLoanExists(lsa)
        returns (DataTypes.LoanData memory)
    {
        return _getLoanStorage().loansByLSA[lsa];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserLoanCount(address user) external view checkZeroAddress(user) returns (uint256) {
        return _getLoanStorage().userLoanCount[user];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserLoanAtIndex(address user, uint256 index) external view checkZeroAddress(user) returns (address) {
        LoanStorageData storage $ = _getLoanStorage();
        if (index >= $.userLoanCount[user]) revert Errors.IndexOutOfBounds();
        return $.userLoanAtIndex[user][index];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserAllLoans(address user) external view checkZeroAddress(user) returns (DataTypes.LoanData[] memory) {
        LoanStorageData storage $ = _getLoanStorage();
        uint256 count = $.userLoanCount[user];
        DataTypes.LoanData[] memory loans = new DataTypes.LoanData[](count);

        for (uint256 i = 0; i < count; i++) {
            address lsa = $.userLoanAtIndex[user][i];
            loans[i] = $.loansByLSA[lsa];
        }

        return loans;
    }

    /**
     * @inheritdoc ILoan
     */
    function getCollateralAsset() external view returns (address) {
        return _getLoanStorage().collateralAsset;
    }

    /**
     * @inheritdoc ILoan
     */
    function getDebtAsset() external view returns (address) {
        return _getLoanStorage().debtAsset;
    }

    /**
     * @inheritdoc ILoan
     */
    function calculateStrikePrice(uint256 loanAmount, uint256 deposit)
        external
        view
        checkZeroAmount(loanAmount)
        checkZeroAmount(deposit)
        returns (uint256 strikePrice)
    {
        LoanStorageData storage $ = _getLoanStorage();
        IPriceOracleGetter oracle = IPriceOracleGetter($.oracle);

        uint256 btcPriceUSD = oracle.getAssetPrice($.btc);
        if (btcPriceUSD == 0) revert Errors.InvalidAssetPrice();

        strikePrice = LoanMath.calculateStrikePrice(btcPriceUSD, loanAmount, deposit);
    }

    /**
     * @inheritdoc ILoan
     */
    function getLoanDetails(uint256 btcAmount, uint256 duration)
        external
        view
        returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired)
    {
        LoanStorageData storage $ = _getLoanStorage();
        DataTypes.CalculateLoanDetailsContext memory ctx = DataTypes.CalculateLoanDetailsContext({
            minBTCAmt: $.minBTCAmt,
            maxBTCAmt: $.maxBTCAmt,
            minDepositBps: $.minDeposit,
            maxDuration: $.maxDuration,
            bitmorPool: $.bitmorPool,
            oracle: $.oracle,
            aavePool: $.aaveV3Pool,
            btc: $.btc,
            debtAsset: $.debtAsset
        });

        (loanAmount, monthlyPayment, minDepositRequired) = LoanLogic.calculateLoanDetails(ctx, btcAmount, duration);
    }

    /**
     * @inheritdoc ILoan
     */
    function getGracePeriod() external view returns (uint256) {
        return _getLoanStorage().gracePeriod;
    }

    function getPremiumCollector() internal view returns (address) {
        return IBitmorAddressesProvider(_getLoanStorage().bitmorAddressesProvider).getPremiumCollector();
    }

    /**
     * @inheritdoc ILoan
     */
    function getRepaymentInterval() external pure returns (uint256) {
        return LOAN_REPAYMENT_INTERVAL;
    }

    /**
     * @inheritdoc IFlashLoanSimpleReceiver
     */
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(_getLoanStorage().aaveAddressesProvider);
    }

    /**
     * @inheritdoc IFlashLoanSimpleReceiver
     */
    function POOL() external view returns (IPool) {
        return IPool(_getLoanStorage().aaveV3Pool);
    }

    /**
     * @inheritdoc ILoan
     */
    function getPreClosureFee() external view returns (uint256) {
        return _getLoanStorage().preClosureFeeBps;
    }

    /// @inheritdoc ILoan
    function getSlippageForSharesToAsset() external view returns (uint256) {
        return _getLoanStorage().slippageSharesToAsset;
    }

    /// @inheritdoc ILoan
    function getSlippageForSwap() external view returns (uint256) {
        return _getLoanStorage().slippageSwap;
    }

    /// @inheritdoc ILoan
    function getMaxBTCAmount() external view returns (uint256) {
        return _getLoanStorage().maxBTCAmt;
    }

    /// @inheritdoc ILoan
    function getMinBTCAmount() external view returns (uint256) {
        return _getLoanStorage().minBTCAmt;
    }

    /// @inheritdoc ILoan
    function getMinDepositBps() external view returns (uint256) {
        return _getLoanStorage().minDeposit;
    }

    /// @inheritdoc ILoan
    function getMaxDuration() external view returns (uint256) {
        return _getLoanStorage().maxDuration;
    }

    /// @inheritdoc ILoan
    function getLiquidationFeeBps() external view returns (uint256) {
        return _getLoanStorage().liquidationFee;
    }

    function getAutoRepayer() internal view returns (address) {
        return IBitmorAddressesProvider(_getLoanStorage().bitmorAddressesProvider).getAutoRepayer();
    }

    function getLoanVaultFactory() internal view returns (address) {
        return IBitmorAddressesProvider(_getLoanStorage().bitmorAddressesProvider).getLoanVaultFactory();
    }

    function getSwapper() internal view returns (address) {
        return IBitmorAddressesProvider(_getLoanStorage().bitmorAddressesProvider).getSwapper();
    }

    function getBitmorAddressesProvider() external view returns (address) {
        return _getLoanStorage().bitmorAddressesProvider;
    }

    // ============ Admin Functions ============

    /// @notice Updates the BitmorAddressesProvider address
    /// @dev BitmorAddressesProvider cannot be set in the constructor due to a circular dependency:
    ///      BitmorAddressesProvider requires Loan's address as an immutable, so Loan must be deployed first.
    ///      This creates an initialization gap between Loan deployment and when this setter is called via
    ///      the timelocked AccessManager operation. During this gap, functions that read from
    ///      BitmorAddressesProvider (initializeLoan, repay, closeLoan, executeOperation) will revert.
    /// @param newBitmorAddressesProvider The new BitmorAddressesProvider contract address
    /// @custom:access Restricted to `LPM_SLOW` role (1-day delay)
    function setBitmorAddressesProvider(address newBitmorAddressesProvider)
        external
        whenNotPaused
        restricted
        checkZeroAddress(newBitmorAddressesProvider)
    {
        _getLoanStorage().bitmorAddressesProvider = newBitmorAddressesProvider;
        emit Loan__BitmorAddressesProviderUpdated(newBitmorAddressesProvider);
    }

    /**
     * @inheritdoc ILoan
     */
    function setGracePeriod(uint256 gracePeriod) external whenNotPaused restricted {
        if (gracePeriod > MAX_GRACE_PERIOD) revert Errors.InvalidInputs();
        _getLoanStorage().gracePeriod = gracePeriod;
        emit Loan__GracePeriodUpdated(gracePeriod);
    }

    /**
     * @inheritdoc ILoan
     */
    function setPreClosureFee(uint256 newFee) external whenNotPaused restricted {
        if (newFee >= BASIS_POINT_SCALE) revert Errors.InvalidFee();
        _getLoanStorage().preClosureFeeBps = newFee;
        emit Loan__PreClosureFeeUpdated(newFee);
    }

    /// @inheritdoc ILoan
    function setSlippageForSharesToAsset(uint256 newSlippage) external whenNotPaused restricted {
        if (newSlippage >= BASIS_POINT_SCALE) revert Errors.InvalidSlippage();
        _getLoanStorage().slippageSharesToAsset = newSlippage;
        emit Loan__SlippageForSharesToAssetUpdated(newSlippage);
    }

    /// @inheritdoc ILoan
    function setSlippageForSwap(uint256 newSlippage) external whenNotPaused restricted {
        if (newSlippage >= BASIS_POINT_SCALE) revert Errors.InvalidSlippage();
        _getLoanStorage().slippageSwap = newSlippage;
        emit Loan__SlippageForSwapUpdated(newSlippage);
    }

    /// @inheritdoc ILoan
    function setMaxBTCAmount(uint256 newMaxBTCAmt) external whenNotPaused restricted {
        LoanStorageData storage $ = _getLoanStorage();
        if (newMaxBTCAmt < $.minBTCAmt) revert Errors.InvalidInputs();
        $.maxBTCAmt = newMaxBTCAmt;
        emit Loan__MaxBTCAmountUpdated(newMaxBTCAmt);
    }

    /// @inheritdoc ILoan
    function setMinBTCAmount(uint256 newMinBTCAmt) external whenNotPaused restricted {
        LoanStorageData storage $ = _getLoanStorage();
        if (newMinBTCAmt > $.maxBTCAmt) revert Errors.InvalidInputs();
        $.minBTCAmt = newMinBTCAmt;
        emit Loan__MinBTCAmountUpdated(newMinBTCAmt);
    }

    /// @inheritdoc ILoan
    function setMinDepositBps(uint256 newMinDepositBps) external whenNotPaused restricted {
        if (newMinDepositBps >= BASIS_POINT_SCALE) revert Errors.InvalidInputs();
        _getLoanStorage().minDeposit = newMinDepositBps;
        emit Loan__MinDepositUpdated(newMinDepositBps);
    }

    /// @inheritdoc ILoan
    function setMaxDuration(uint256 newMaxDuration) external whenNotPaused restricted checkZeroAmount(newMaxDuration) {
        _getLoanStorage().maxDuration = newMaxDuration;
        emit Loan__MaxDurationUpdated(newMaxDuration);
    }

    /// @inheritdoc ILoan
    function setLiquidationFeeBps(uint256 newLiquidationFeeBps) external whenNotPaused restricted {
        if (newLiquidationFeeBps > MAX_LIQUIDATION_FEE) revert Errors.InvalidFee();
        _getLoanStorage().liquidationFee = newLiquidationFeeBps;
        emit Loan__LiquidationFeeUpdated(newLiquidationFeeBps);
    }

    /**
     * @notice Pauses the contract in case of emergency
     * @custom:access Restricted to `LPM_FAST` role
     */
    function pause() external whenNotPaused restricted {
        _pause();
    }

    /**
     * @notice Unpauses the contract to resume normal operations
     * @custom:access Restricted to `LPM_SLOW` role
     */
    function unpause() external whenPaused restricted {
        _unpause();
    }

    /// @inheritdoc ILoan
    function claimSurplusCollateral(address _lsa)
        external
        whenNotPaused
        nonReentrant
        checkZeroAddress(_lsa)
        checkIfLoanExists(_lsa)
        returns (uint256 assetsClaimed)
    {
        LoanStorageData storage $ = _getLoanStorage();
        DataTypes.LoanData storage loanData = $.loansByLSA[_lsa];

        assetsClaimed = LoanLogic.executeClaimRemainingCollateral(
            _lsa,
            loanData.borrower,
            loanData.status,
            $.bitmorPool,
            $.debtAsset,
            $.collateralAsset,
            $.slippageSharesToAsset
        );

        emit Loan__SurplusCollateralClaimed(_lsa, loanData.borrower, assetsClaimed);
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal validation for zero amounts
     * @dev Reverts with `Errors.ZeroAmount()` if amt is zero
     * @param amt The amount to validate
     */
    function _checkZeroAmount(uint256 amt) internal pure {
        if (amt == 0) {
            revert Errors.ZeroAmount();
        }
    }

    /**
     * @notice Internal validation for zero addresses
     * @dev Reverts with `Errors.ZeroAddress()` if _add is zero address
     * @param _add The address to validate
     */
    function _checkZeroAddress(address _add) internal pure {
        if (_add == address(0)) {
            revert Errors.ZeroAddress();
        }
    }

    /**
     * @notice Internal check for loan existence
     * @dev Reverts with `Errors.LoanDoesNotExists()` if no loan found for LSA
     * @param _lsa The Loan Specific Address to check
     */
    function _checkIfLoanExists(address _lsa) internal view {
        if (_getLoanStorage().loansByLSA[_lsa].borrower == address(0)) {
            revert Errors.LoanDoesNotExists();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
