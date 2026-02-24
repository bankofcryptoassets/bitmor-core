// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title LoanStorage
 * @author Bitmor Protocol
 * @notice Storage layout for Bitmor Protocol loan management
 * @dev Contains all state variables for tracking loans and protocol configuration.
 *
 * ## Storage Design
 * - Immutable addresses for core protocol integrations (Aave, Bitmor Pool, Oracle)
 * - Mutable addresses for upgradeable components (swap adapter, factory)
 * - Loan data mapped by Loan Specific Address (LSA)
 * - User loan indexing for multi-loan support
 *
 * @custom:security All immutable addresses are validated in constructor
 */
contract LoanStorage {
    // ============ Immutable Protocol Addresses ============

    /**
     * @notice Aave V3 pool address for flash loan operations
     */
    address public immutable i_AAVE_V3_POOL;

    /**
     * @notice Address provider required for flash loan compatibility
     */
    address public immutable i_AAVE_ADDRESSES_PROVIDER;

    /**
     * @notice Bitmor Lending Pool address for collateral deposits and debt borrowing
     */
    address public immutable i_BITMOR_POOL;

    /**
     * @notice Oracle address to get prices for the assets.
     * @dev Same oracle address is utilized in BLP.
     */
    address public immutable i_ORACLE;

    /// @notice Collateral asset address (bvBTC)
    address internal immutable i_COLLATERAL_ASSET;

    /// @notice Debt asset address (USDC)
    address internal immutable i_DEBT_ASSET;

    /// @notice cbBTC (Coinbase Wrapped Bitcoin) address
    address internal immutable i_BTC;

    // ============ Protocol Contract Addresses ============

    /**
     * @notice Factory contract for deploying Loan Specific Address (LSAs)
     */
    address public s_loanVaultFactory;

    /// @notice Swapper contract for executing token swaps

    address public s_swapper;

    /**
     * @notice Collects insurance premium amount.
     */
    address internal s_premiumCollector;

    /// @notice Collects fee on liquidation from Liquidation Bonus.
    address internal s_liquidationFeeCollector;

    /**
     * @notice Grace period for monthly installments in `seconds`.
     */
    uint256 internal s_gracePeriod;

    /**
     * @notice Fee for pre closing loan. (in bps)
     */
    uint256 internal s_preClosureFeeBps;

    /// @notice Fee on liquidation. This is implemented on liquidation bonus.
    uint256 internal s_liquidationFee;

    /// @notice Slippage in BPS while convert `bvBTC` shares to cbBTC.
    uint256 internal s_slippage_sharesToAsset;

    /// @notice Slippage in BPS while swapping.
    uint256 internal s_slippage_swap;

    /// @notice Max cbBTC amount for a loan.
    uint256 internal s_maxBTCAmt;

    /// @notice Min. cbBTC amount for a loan.
    uint256 internal s_minBTCAmt;

    /// @notice Min % of deposit user need to make of the BTC amount in bps.
    uint256 internal s_minDeposit;

    /// @notice Maximum loan duration in months
    uint256 internal s_maxDuration;

    // ============ Storage Mappings ============

    /**
     * @notice Maps LSA addresses to their loan data
     * @dev Primary storage for all loan information.
     *
     * Status transition invariants on `s_loansByLSA[lsa].status`:
     * - MUST be set to `Active` upon loan creation
     * - Transitions MUST be monotonic: Active -> Completed or Active -> Liquidated
     * - MUST NOT transition from Completed or Liquidated back to Active
     * - MUST NOT transition from Completed to Liquidated or vice versa
     */
    mapping(address => DataTypes.LoanData) internal s_loansByLSA;

    /**
     * @notice Tracks the total number of loans created by each user
     * @dev Used to index and iterate through user's loans
     */
    mapping(address => uint256) public s_userLoanCount;

    /**
     * @notice Maps user address and index to their LSA addresses
     * @dev Enables retrieval of user's Nth loan: s_userLoanAtIndex[user][0] returns first loan's LSA
     */
    mapping(address => mapping(uint256 => address)) public s_userLoanAtIndex;

    // ============ Constants ============

    /**
     * @notice Loan repayment interval in seconds (30 days)
     */
    uint256 internal constant LOAN_REPAYMENT_INTERVAL = 30 days;

    /**
     * @notice Initial Insurance ID
     */
    uint256 internal constant INITIAL_INSURANCE_ID = 0;

    /// @notice 20% is the Max Liqudiation Fee on liquidation bonus.
    uint256 internal constant MAX_LIQUIDATION_FEE = 20_00;

    /// @notice Basis point scale (10000 bps = 100%), used as upper bound for all BPS parameters
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    /// @notice Maximum allowed grace period (45 days)
    uint256 internal constant MAX_GRACE_PERIOD = 45 days;

    // ============ Constructor ============

    /**
     * @notice Initializes the storage contract with immutable protocol addresses
     * @param _aaveV3Pool Aave V3 pool address (for flash loans)
     * @param _aaveAddressesProvider Aave V3 addresses provider (for flash loan compatibility)
     * @param _bitmorPool Bitmor Lending Pool
     * @param _oracle Price Oracle
     * @param _collateralAsset Collateral asset address (bvBTC)
     * @param _debtAsset Debt asset address (USDC)
     * @param _btc Wrapped Bitcoin address (cbBTC)
     */
    constructor(
        address _aaveV3Pool,
        address _aaveAddressesProvider,
        address _bitmorPool,
        address _oracle,
        address _collateralAsset,
        address _debtAsset,
        address _btc
    ) {
        if (
            _aaveV3Pool == address(0) || _aaveAddressesProvider == address(0) || _bitmorPool == address(0)
                || _oracle == address(0) || _collateralAsset == address(0) || _debtAsset == address(0) || _btc == address(0)
        ) revert Errors.ZeroAddress();

        i_AAVE_V3_POOL = _aaveV3Pool;
        i_BITMOR_POOL = _bitmorPool;
        i_ORACLE = _oracle;
        i_COLLATERAL_ASSET = _collateralAsset;
        i_DEBT_ASSET = _debtAsset;
        i_AAVE_ADDRESSES_PROVIDER = _aaveAddressesProvider;
        i_BTC = _btc;
    }
}
