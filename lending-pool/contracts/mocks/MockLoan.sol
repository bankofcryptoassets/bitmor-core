// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {ILoan} from "../interfaces/ILoan.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";

/**
 * @title MockLoan
 * @notice Mock implementation of ILoan for testing liquidation logic
 * @dev Allows tests to set loan state and verify liquidation behavior
 *
 * Key features:
 * - Store/retrieve LoanData per LSA address
 * - Configurable gracePeriod and repaymentInterval
 * - Test helpers to manipulate loan state
 * - Tracks updateLoanData calls for verification
 */
contract MockLoan is ILoan {
    // ========== STATE ==========

    /// @dev Loan data per LSA address
    mapping(address => DataTypes.LoanData) private _loanData;

    /// @dev Whether a loan exists for an LSA
    mapping(address => bool) private _loanExists;

    /// @dev Configurable grace period (default 7 days)
    uint256 private _gracePeriod = 7 days;

    /// @dev Repayment interval (constant 30 days)
    uint256 private constant REPAYMENT_INTERVAL = 30 days;

    /// @dev Collateral asset address (bvBTC)
    address private _collateralAsset;

    /// @dev Debt asset address (USDC)
    address private _debtAsset;

    /// @notice Track micro liquidation calls for testing
    mapping(address => uint256) public microLiquidationCount;

    /// @notice Track full liquidation calls for testing
    mapping(address => uint256) public fullLiquidationCount;

    // ========== CONSTRUCTOR ==========

    constructor(address collateralAsset_, address debtAsset_) public {
        _collateralAsset = collateralAsset_;
        _debtAsset = debtAsset_;
    }

    // ========== ILoan IMPLEMENTATION ==========

    /**
     * @notice Get loan data for an LSA
     * @param lsa The loan smart account address
     * @return The loan data struct
     */
    function getLoanByLSA(address lsa) external view override returns (DataTypes.LoanData memory) {
        return _loanData[lsa];
    }

    /**
     * @notice Get the grace period for overdue determination
     * @return Grace period in seconds
     */
    function getGracePeriod() external view override returns (uint256) {
        return _gracePeriod;
    }

    /**
     * @notice Get the repayment interval (30 days)
     * @return Repayment interval in seconds
     */
    function getRepaymentInterval() external view override returns (uint256) {
        return REPAYMENT_INTERVAL;
    }

    /**
     * @notice Get the collateral asset address (bvBTC)
     * @return Collateral asset address
     */
    function getCollateralAsset() external view override returns (address) {
        return _collateralAsset;
    }

    /**
     * @notice Get the debt asset address (USDC)
     * @return Debt asset address
     */
    function getDebtAsset() external view override returns (address) {
        return _debtAsset;
    }

    /**
     * @notice Called by LendingPoolCollateralManager after micro liquidation
     * @param lsa The loan smart account address
     */
    function updateLoanDataForMicroLiquidation(address lsa) external override {
        require(_loanExists[lsa], "MockLoan: LOAN_NOT_EXISTS");

        // Reduce duration by 1
        if (_loanData[lsa].duration > 0) {
            _loanData[lsa].duration = _loanData[lsa].duration - 1;
        }

        // Update last payment timestamp
        _loanData[lsa].lastPaymentTimestamp = block.timestamp;

        // Track call for testing
        microLiquidationCount[lsa]++;
    }

    /**
     * @notice Called by LendingPoolCollateralManager after full liquidation
     * @param lsa The loan smart account address
     */
    function updateLoanDataForFullLiquidation(address lsa) external override {
        require(_loanExists[lsa], "MockLoan: LOAN_NOT_EXISTS");

        // Set duration to 0
        _loanData[lsa].duration = 0;

        // Set status to Liquidated
        _loanData[lsa].status = DataTypes.LoanStatus.Liquidated;

        // Update timestamp
        _loanData[lsa].lastPaymentTimestamp = block.timestamp;

        // Track call for testing
        fullLiquidationCount[lsa]++;
    }

    // ========== STUB IMPLEMENTATIONS (not used in liquidation tests) ==========

    function initializeLoan(
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external override returns (address) {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function updateInsuranceId(address, uint256) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function getUserLoanCount(address) external view override returns (uint256) {
        return 0;
    }

    function getUserLoanAtIndex(address, uint256) external view override returns (address) {
        return address(0);
    }

    function getUserAllLoans(address) external view override returns (DataTypes.LoanData[] memory) {
        DataTypes.LoanData[] memory empty;
        return empty;
    }

    function calculateStrikePrice(uint256, uint256) external view override returns (uint256) {
        return 0;
    }

    function repay(address, uint256) external override returns (uint256) {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function closeLoan(address, bool) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function setLoanVaultFactory(address) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function setSwapAdapter(address) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function setZQuoter(address) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function setPremiumCollector(address) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function getPremiumCollector() external view override returns (address) {
        return address(0);
    }

    function setGracePeriod(uint256) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function getPreClosureFee() external view override returns (uint256) {
        return 0;
    }

    function setPreClosureFee(uint256) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function setLiquidationBuffer(uint256) external override {
        revert("MockLoan: NOT_IMPLEMENTED");
    }

    function getLiquidationBuffer() external view override returns (uint256) {
        return 0;
    }

    function getLoanDetails(uint256, uint256)
        external
        view
        override
        returns (uint256, uint256, uint256)
    {
        return (0, 0, 0);
    }

    // ========== TEST HELPERS ==========

    /**
     * @notice Create an active loan for testing
     * @param lsa The loan smart account address
     * @param borrower The borrower address
     * @param collateralAmount Amount of collateral (bvBTC)
     * @param loanAmount Total loan amount (USDC)
     * @param duration Loan duration in months
     * @param monthlyPayment Estimated monthly payment (USDC)
     */
    function createActiveLoan(
        address lsa,
        address borrower,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 duration,
        uint256 monthlyPayment
    ) external {
        _loanData[lsa] = DataTypes.LoanData({
            borrower: borrower,
            depositAmount: loanAmount / 3, // ~33% deposit
            loanAmount: loanAmount,
            collateralAmount: collateralAmount,
            estimatedMonthlyPayment: monthlyPayment,
            duration: duration,
            createdAt: block.timestamp,
            insuranceID: 0,
            lastPaymentTimestamp: block.timestamp,
            status: DataTypes.LoanStatus.Active
        });
        _loanExists[lsa] = true;
    }

    /**
     * @notice Set complete loan data (for complex test scenarios)
     */
    function setLoanData(address lsa, DataTypes.LoanData memory data) external {
        _loanData[lsa] = data;
        _loanExists[lsa] = true;
    }

    /**
     * @notice Set loan status
     */
    function setLoanStatus(address lsa, DataTypes.LoanStatus status) external {
        _loanData[lsa].status = status;
    }

    /**
     * @notice Set insurance ID (0 = uninsured)
     */
    function setInsuranceId(address lsa, uint256 insuranceId) external {
        _loanData[lsa].insuranceID = insuranceId;
    }

    /**
     * @notice Set last payment timestamp (for overdue testing)
     */
    function setLastPaymentTimestamp(address lsa, uint256 timestamp) external {
        _loanData[lsa].lastPaymentTimestamp = timestamp;
    }

    /**
     * @notice Set collateral amount
     */
    function setCollateralAmount(address lsa, uint256 amount) external {
        _loanData[lsa].collateralAmount = amount;
    }

    /**
     * @notice Set estimated monthly payment
     */
    function setEstimatedMonthlyPayment(address lsa, uint256 amount) external {
        _loanData[lsa].estimatedMonthlyPayment = amount;
    }

    /**
     * @notice Set loan duration
     */
    function setDuration(address lsa, uint256 duration) external {
        _loanData[lsa].duration = duration;
    }

    /**
     * @notice Set grace period (test helper)
     */
    function setGracePeriodValue(uint256 gracePeriod_) external {
        _gracePeriod = gracePeriod_;
    }

    /**
     * @notice Set collateral asset address
     */
    function setCollateralAssetAddress(address collateralAsset_) external {
        _collateralAsset = collateralAsset_;
    }

    /**
     * @notice Set debt asset address
     */
    function setDebtAssetAddress(address debtAsset_) external {
        _debtAsset = debtAsset_;
    }

    /**
     * @notice Check if loan exists
     */
    function loanExists(address lsa) external view returns (bool) {
        return _loanExists[lsa];
    }

    /**
     * @notice Make loan overdue by setting lastPaymentTimestamp in the past
     * @param lsa The loan smart account address
     * @param daysOverdue Number of days past due date
     */
    function makeLoanOverdue(address lsa, uint256 daysOverdue) external {
        require(_loanExists[lsa], "MockLoan: LOAN_NOT_EXISTS");
        // Set timestamp such that: lastPayment + grace + interval < now
        // So: lastPayment = now - grace - interval - daysOverdue
        uint256 overdueTime = _gracePeriod + REPAYMENT_INTERVAL + (daysOverdue * 1 days);
        _loanData[lsa].lastPaymentTimestamp = block.timestamp - overdueTime;
    }
}
