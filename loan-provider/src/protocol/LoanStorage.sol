// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {DataTypes} from "../libraries/types/DataTypes.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title LoanStorage
 * @notice Storage layout for Bitmor Protocol loan management
 * @dev Contains all state variables for tracking loans and protocol configuration
 */
contract LoanStorage {
    // ============ Immutable Protocol Addresses ============

    /// @notice Aave V3 pool address for flash loan operations
    address public immutable i_AAVE_V3_POOL;

    /// @notice Adddress provider required for flash loan compatibility
    address public immutable i_AAVE_ADDRESSES_PROVIDER;

    /// @notice Bitmor Lending Pool address for collateral deposits and debt borrowing
    address public immutable i_BITMOR_POOL;

    /// @notice Aave V2 addresses provider for accessing protocol contracts (oracle, etc.)
    address public immutable i_ORACLE;

    /// @notice Collateral asset address (cbBTC)
    address internal immutable i_COLLATERAL_ASSET;

    /// @notice Debt asset address (USDC)
    address internal immutable i_DEBT_ASSET;

    // ============ Protocol Contract Addresses ============

    /// @notice Factory contract for deploying Loan Specific Address (LSAs)
    address public s_loanVaultFactory;

    /// @notice Swap adapter contract for executing token swaps
    address public s_swapAdapter;

    /// @notice zQuoter contract for price quotation (Aerodrome DEX)
    address public s_zQuoter; //0x772E2810A471dB2CC7ADA0d37D6395476535889a on Base

    /// @notice Collects insurance premium amount.
    address internal s_premiumCollector;

    /// @notice Grace period for monthly installments in `days`
    uint256 internal s_gracePeriod;

    /// @notice Fee for pre closing loan. (in bps)
    uint256 internal s_preClosureFeeBps;

    // ============ Storage Mappings ============

    /// @notice Maps LSA addresses to their loan data
    /// @dev Primary storage for all loan information
    mapping(address => DataTypes.LoanData) internal s_loansByLSA;

    /// @notice Tracks the total number of loans created by each user
    /// @dev Used to index and iterate through user's loans
    mapping(address => uint256) public s_userLoanCount;

    /// @notice Maps user address and index to their LSA addresses
    /// @dev Enables retrieval of user's Nth loan: s_userLoanAtIndex[user][0] returns first loan's LSA
    mapping(address => mapping(uint256 => address)) public s_userLoanAtIndex;

    // ============ Constants ============

    /// @notice Maximum slippage tolerance in basis points (50 = 0.5%)
    uint256 public constant MAX_SLIPPAGE_BPS = 50;

    /// @notice Loan repayment interval in seconds (30 days)
    uint256 internal constant LOAN_REPAYMENT_INTERVAL = 30 days;

    /// @notice MAX collateral amount user can take.
    uint256 public constant MAX_COLLATERAL_AMOUNT = 1 * 1e8;

    /// @notice Initial Insurance ID
    uint256 public constant INITIAL_INSURANCE_ID = 0;

    // ============ Constructor ============

    /**
     * @notice Initializes the storage contract with immutable protocol addresses
     * @param _aaveV3Pool Aave V3 pool address (for flash loans)
     * @param _bitmorPool Bitmor Lending Pool
     * @param _oracle Price Oracle
     * @param _collateralAsset Collateral asset address (cbBTC)
     * @param _debtAsset Debt asset address (USDC)
     */
    constructor(
        address _aaveV3Pool,
        address _aaveAddressesProvider,
        address _bitmorPool,
        address _oracle,
        address _collateralAsset,
        address _debtAsset
    ) {
        if (
            _aaveV3Pool == address(0) || _bitmorPool == address(0) || _oracle == address(0)
                || _collateralAsset == address(0) || _debtAsset == address(0)
        ) revert Errors.ZeroAddress();

        i_AAVE_V3_POOL = _aaveV3Pool;
        i_BITMOR_POOL = _bitmorPool;
        i_ORACLE = _oracle;
        i_COLLATERAL_ASSET = _collateralAsset;
        i_DEBT_ASSET = _debtAsset;
        i_AAVE_ADDRESSES_PROVIDER = _aaveAddressesProvider;
    }
}
