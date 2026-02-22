// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {AccessManaged} from "@openzeppelin/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

import {LoanLogic, LoanMath} from "../libraries/logic/LoanLogic.sol";
import {LSALogic} from "../libraries/logic/LSALogic.sol";
import {IPriceOracleGetter} from "../interfaces/IPriceOracleGetter.sol";
import {OracleLogic} from "../libraries/logic/OracleLogic.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";
import {RepayLogic} from "../libraries/logic/RepayLogic.sol";
import {CloseLoanLogic} from "../libraries/logic/CloseLoanLogic.sol";
import {FlashLoanLogic} from "../libraries/logic/FlashLoanLogic.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import {ILoan} from "../interfaces/ILoan.sol";
import {IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimpleReceiver.sol";
import {IPool, IPoolAddressesProvider} from "../interfaces/IPool.sol";

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
 * 5. cbBTC collateral is deposited to Bitmor Lending Pool
 * 6. User repays monthly via `repay()` or closes early via `closeLoan()`
 *
 * @custom:security Uses reentrancy guards, access control, and pausability for secure operations
 * @custom:security Flash loan callback validates caller is Aave V3 pool and initiator is this contract
 */
contract Loan is LoanStorage, ILoan, ReentrancyGuard, IFlashLoanSimpleReceiver, AccessManaged, Pausable {
    using LoanLogic for mapping(address => DataTypes.LoanData);
    using LSALogic for address;

    // ============ Constructor ============

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
     * @param _swapper Swapper contract address for token swaps
     * @param _premiumCollector Address that collects insurance premiums
     * @param _preClosureFeeBps Loan pre-closure fee (in bps)
     * @param _gracePeriod Grace period for monthly payment in seconds
     */
    constructor(
        address _manager,
        address _aaveV3Pool,
        address _aaveAddressesProvider,
        address _bitmorPool,
        address _oracle,
        address _collateralAsset,
        address _debtAsset,
        address _btc,
        address _swapper,
        address _premiumCollector,
        uint256 _preClosureFeeBps,
        uint256 _gracePeriod
    )
        LoanStorage(_aaveV3Pool, _aaveAddressesProvider, _bitmorPool, _oracle, _collateralAsset, _debtAsset, _btc)
        AccessManaged(_manager)
    {
        if (_swapper == address(0) || _premiumCollector == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_preClosureFeeBps >= BASIS_POINT_SCALE) revert Errors.InvalidFee();
        if (_gracePeriod > MAX_GRACE_PERIOD) revert Errors.InvalidInputs();

        s_swapper = _swapper;
        s_premiumCollector = _premiumCollector;
        s_preClosureFeeBps = _preClosureFeeBps;
        s_gracePeriod = _gracePeriod;
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
        uint256 collateralAmount,
        uint256 duration,
        bytes calldata data
    ) external whenNotPaused restricted nonReentrant returns (address lsa) {
        DataTypes.InitializeLoanContext memory ctx = DataTypes.InitializeLoanContext({
            bitmorPool: i_BITMOR_POOL,
            oracle: i_ORACLE,
            collateralAsset: i_COLLATERAL_ASSET,
            debtAsset: i_DEBT_ASSET,
            aavePool: i_AAVE_V3_POOL,
            loanVaultFactory: s_loanVaultFactory,
            premiumCollector: s_premiumCollector,
            minCollateralAmt: s_minBTCAmt,
            maxCollateralAmt: s_maxBTCAmt,
            loanRepaymentInterval: LOAN_REPAYMENT_INTERVAL,
            minDepositBps: s_minDeposit,
            maxDuration: s_maxDuration,
            maxOracleStaleness: s_maxOracleStaleness
        });

        lsa = s_loansByLSA.executeInitializeLoan(
            s_userLoanCount,
            s_userLoanAtIndex,
            ctx,
            DataTypes.ExecuteInitializeLoanParams(
                msg.sender, depositAmount, premiumAmount, collateralAmount, duration, INITIAL_INSURANCE_ID, data
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
        finalAmountRepaid = RepayLogic.executeRepay(
            i_BITMOR_POOL,
            i_DEBT_ASSET,
            i_COLLATERAL_ASSET,
            DataTypes.ExecuteRepayParams(lsa, amount, s_slippage_sharesToAsset),
            s_loansByLSA
        );
    }

    // ============ Close Loan Function  ============

    /**
     * @inheritdoc ILoan
     */
    function closeLoan(address lsa, bool withdrawInBTC) external whenNotPaused nonReentrant {
        DataTypes.ExecuteCloseLoanContext memory ctx = DataTypes.ExecuteCloseLoanContext(
            i_BITMOR_POOL,
            i_AAVE_V3_POOL,
            i_ORACLE,
            i_DEBT_ASSET,
            i_COLLATERAL_ASSET,
            i_BTC,
            s_preClosureFeeBps,
            s_slippage_swap,
            s_maxOracleStaleness
        );
        DataTypes.ExecuteCloseLoanParams memory params = DataTypes.ExecuteCloseLoanParams(lsa, withdrawInBTC);
        CloseLoanLogic.executeCloseLoan(ctx, params, s_loansByLSA);
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
        s_loansByLSA.updateInsuranceId(lsa, insuranceID);
        emit Loan__InsuranceIDUpdated(lsa, insuranceID);
    }

    /**
     * @inheritdoc ILoan
     */
    function updateLoanDataForMicroLiquidation(address _lsa) external whenNotPaused restricted checkZeroAddress(_lsa) {
        uint256 newDuration = s_loansByLSA.updateLoanDataForMicroLiquidation(_lsa);
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
        s_loansByLSA.updateLoanForMicroLiquidationCompletion(_lsa);

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
        s_loansByLSA.updateLoanDataForFullLiquidation(_lsa);

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

        DataTypes.ExecuteFLOperationContext memory ctx = DataTypes.ExecuteFLOperationContext(
            i_AAVE_V3_POOL,
            i_BITMOR_POOL,
            s_swapper,
            i_DEBT_ASSET,
            i_COLLATERAL_ASSET,
            i_BTC,
            s_premiumCollector,
            i_ORACLE,
            s_slippage_swap
        );

        DataTypes.ExecuteFLOperationParams memory flOpParams =
            DataTypes.ExecuteFLOperationParams(asset, amount, premium, initiator, flData, s_slippage_sharesToAsset);

        if (initializingLoan) {
            FlashLoanLogic.executeFLOperationInitiailizingLoan(ctx, flOpParams, s_loansByLSA);
        } else {
            FlashLoanLogic.executeFLOperationCloseLoan(ctx, flOpParams, s_loansByLSA);
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
        return s_loansByLSA[lsa];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserLoanCount(address user) external view checkZeroAddress(user) returns (uint256) {
        return s_userLoanCount[user];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserLoanAtIndex(address user, uint256 index) external view checkZeroAddress(user) returns (address) {
        if (index >= s_userLoanCount[user]) revert Errors.IndexOutOfBounds();
        return s_userLoanAtIndex[user][index];
    }

    /**
     * @inheritdoc ILoan
     */
    function getUserAllLoans(address user) external view checkZeroAddress(user) returns (DataTypes.LoanData[] memory) {
        uint256 count = s_userLoanCount[user];
        DataTypes.LoanData[] memory loans = new DataTypes.LoanData[](count);

        for (uint256 i = 0; i < count; i++) {
            address lsa = s_userLoanAtIndex[user][i];
            loans[i] = s_loansByLSA[lsa];
        }

        return loans;
    }

    /**
     * @inheritdoc ILoan
     */
    function getCollateralAsset() external view returns (address) {
        return i_COLLATERAL_ASSET;
    }

    /**
     * @inheritdoc ILoan
     */
    function getDebtAsset() external view returns (address) {
        return i_DEBT_ASSET;
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
        uint256 btcPriceUSD = OracleLogic.getValidatedPrice(i_ORACLE, i_COLLATERAL_ASSET, s_maxOracleStaleness);

        strikePrice = LoanMath.calculateStrikePrice(btcPriceUSD, loanAmount, deposit);
    }

    /**
     * @inheritdoc ILoan
     */
    function getLoanDetails(uint256 collateralAmount, uint256 duration)
        external
        view
        returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired)
    {
        (loanAmount, monthlyPayment, minDepositRequired) = LoanLogic.calculateLoanDetails(
            DataTypes.CalculateLoanDetailsContext(
                s_minBTCAmt,
                s_maxBTCAmt,
                s_minDeposit,
                s_maxDuration,
                i_BITMOR_POOL,
                i_ORACLE,
                i_AAVE_V3_POOL,
                i_COLLATERAL_ASSET,
                i_DEBT_ASSET,
                s_maxOracleStaleness
            ),
            collateralAmount,
            duration
        );
    }

    /**
     * @inheritdoc ILoan
     */
    function getGracePeriod() external view returns (uint256) {
        return s_gracePeriod;
    }

    /**
     * @inheritdoc ILoan
     */
    function getPremiumCollector() external view returns (address) {
        return s_premiumCollector;
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
        return IPoolAddressesProvider(i_AAVE_ADDRESSES_PROVIDER);
    }

    /**
     * @inheritdoc IFlashLoanSimpleReceiver
     */
    function POOL() external view returns (IPool) {
        return IPool(i_AAVE_V3_POOL);
    }

    /**
     * @inheritdoc ILoan
     */
    function getPreClosureFee() external view returns (uint256) {
        return s_preClosureFeeBps;
    }

    /// @inheritdoc ILoan
    function getSlippageForSharesToAsset() external view returns (uint256) {
        return s_slippage_sharesToAsset;
    }

    /// @inheritdoc ILoan
    function getSlippageForSwap() external view returns (uint256) {
        return s_slippage_swap;
    }

    /// @inheritdoc ILoan
    function getMaxBTCAmount() external view returns (uint256) {
        return s_maxBTCAmt;
    }

    /// @inheritdoc ILoan
    function getMinBTCAmount() external view returns (uint256) {
        return s_minBTCAmt;
    }

    /// @inheritdoc ILoan
    function getMinDepositBps() external view returns (uint256) {
        return s_minDeposit;
    }

    /// @inheritdoc ILoan
    function getMaxDuration() external view returns (uint256) {
        return s_maxDuration;
    }

    /// @inheritdoc ILoan
    function getMaxOracleStaleness() external view returns (uint256) {
        return s_maxOracleStaleness;
    }

    /// @inheritdoc ILoan
    function getLiquidationFeeBps() external view returns (uint256) {
        return s_liquidationFee;
    }

    /// @inheritdoc ILoan
    function getLiquidationFeeCollector() external view returns (address) {
        return s_liquidationFeeCollector;
    }

    // ============ Admin Functions ============

    /**
     * @inheritdoc ILoan
     */
    function setLoanVaultFactory(address newFactory) external whenNotPaused restricted checkZeroAddress(newFactory) {
        s_loanVaultFactory = newFactory;
        emit Loan__LoanVaultFactoryUpdated(newFactory);
    }

    /**
     * @inheritdoc ILoan
     */
    function setSwapper(address newSwapper) external whenNotPaused restricted checkZeroAddress(newSwapper) {
        s_swapper = newSwapper;
        emit Loan__SwapperUpdated(newSwapper);
    }

    /**
     * @inheritdoc ILoan
     */
    function setPremiumCollector(address newPremiumCollector)
        external
        whenNotPaused
        restricted
        checkZeroAddress(newPremiumCollector)
    {
        s_premiumCollector = newPremiumCollector;
        emit Loan__PremiumCollectorUpdated(s_premiumCollector);
    }

    /**
     * @inheritdoc ILoan
     */
    function setGracePeriod(uint256 gracePeriod) external whenNotPaused restricted {
        if (gracePeriod > MAX_GRACE_PERIOD) revert Errors.InvalidInputs();
        s_gracePeriod = gracePeriod;
        emit Loan__GracePeriodUpdated(gracePeriod);
    }

    /**
     * @inheritdoc ILoan
     */
    function setPreClosureFee(uint256 newFee) external whenNotPaused restricted {
        if (newFee >= BASIS_POINT_SCALE) revert Errors.InvalidFee();
        s_preClosureFeeBps = newFee;
        emit Loan__PreClosureFeeUpdated(newFee);
    }

    /// @inheritdoc ILoan
    function setSlippageForSharesToAsset(uint256 newSlippage) external whenNotPaused restricted {
        if (newSlippage >= BASIS_POINT_SCALE) revert Errors.InvalidSlippage();
        s_slippage_sharesToAsset = newSlippage;
        emit Loan__SlippageForSharesToAssetUpdated(newSlippage);
    }

    /// @inheritdoc ILoan
    function setSlippageForSwap(uint256 newSlippage) external whenNotPaused restricted {
        if (newSlippage >= BASIS_POINT_SCALE) revert Errors.InvalidSlippage();
        s_slippage_swap = newSlippage;
        emit Loan__SlippageForSwapUpdated(newSlippage);
    }

    /// @inheritdoc ILoan
    function setMaxBTCAmount(uint256 newMaxBTCAmt) external whenNotPaused restricted {
        if (newMaxBTCAmt < s_minBTCAmt) revert Errors.InvalidInputs();
        s_maxBTCAmt = newMaxBTCAmt;
        emit Loan__MaxBTCAmountUpdated(newMaxBTCAmt);
    }

    /// @inheritdoc ILoan
    function setMinBTCAmount(uint256 newMinBTCAmt) external whenNotPaused restricted {
        if (newMinBTCAmt > s_maxBTCAmt) revert Errors.InvalidInputs();
        s_minBTCAmt = newMinBTCAmt;
        emit Loan__MinBTCAmountUpdated(newMinBTCAmt);
    }

    /// @inheritdoc ILoan
    function setMinDepositBps(uint256 newMinDepositBps) external whenNotPaused restricted {
        if (newMinDepositBps >= BASIS_POINT_SCALE) revert Errors.InvalidInputs();
        s_minDeposit = newMinDepositBps;
        emit Loan__MinDepositUpdated(newMinDepositBps);
    }

    /// @inheritdoc ILoan
    function setMaxDuration(uint256 newMaxDuration) external whenNotPaused restricted checkZeroAmount(newMaxDuration) {
        s_maxDuration = newMaxDuration;
        emit Loan__MaxDurationUpdated(newMaxDuration);
    }

    /// @inheritdoc ILoan
    function setMaxOracleStaleness(uint256 newMaxStaleness) external whenNotPaused restricted {
        if (newMaxStaleness == 0) revert Errors.ZeroAmount();
        if (newMaxStaleness > MAX_ORACLE_STALENESS) revert Errors.InvalidInputs();
        s_maxOracleStaleness = newMaxStaleness;
        emit Loan__MaxOracleStalenessUpdated(newMaxStaleness);
    }

    /// @inheritdoc ILoan
    function setLiquidationFeeBps(uint256 newLiquidationFeeBps) external whenNotPaused restricted {
        if (newLiquidationFeeBps > MAX_LIQUIDATION_FEE) revert Errors.InvalidFee();
        s_liquidationFee = newLiquidationFeeBps;
        emit Loan__LiquidationFeeUpdated(newLiquidationFeeBps);
    }

    /// @inheritdoc ILoan
    function setLiquidationFeeCollector(address newLiquidationFeeCollector)
        external
        whenNotPaused
        restricted
        checkZeroAddress(newLiquidationFeeCollector)
    {
        s_liquidationFeeCollector = newLiquidationFeeCollector;
        emit Loan__LiquidationFeeCollectorUpdated(newLiquidationFeeCollector);
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
        DataTypes.LoanData storage loanData = s_loansByLSA[_lsa];

        assetsClaimed = LoanLogic.executeClaimRemainingCollateral(
            _lsa,
            loanData.borrower,
            loanData.status,
            i_BITMOR_POOL,
            i_DEBT_ASSET,
            i_COLLATERAL_ASSET,
            s_slippage_sharesToAsset
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
        if (s_loansByLSA[_lsa].borrower == address(0)) {
            revert Errors.LoanDoesNotExists();
        }
    }
}
