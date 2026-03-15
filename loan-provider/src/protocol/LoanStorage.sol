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

    bytes32 internal constant LOAN_STORAGE_LOCATION =
        0xb8edd834a76951e77f534a97f5158809f53c7eb2b7458c00ae214c5615e88d00;

    /// @custom:storage-location erc7201:bitmor.storage.Loan
    struct LoanStorageData {
        // ── Slot 0 (32B): Aave V3 pool + BTC upper bound + grace period
        address aaveV3Pool; // 20B
        uint64 maxBTCAmt; // 8B  | max 21M BTC × 1e8 = 2.1e15
        uint32 gracePeriod; // 4B  | max 45 days = 3,888,000s
        // ── Slot 1 (32B): Aave addresses provider + BTC lower bound + fee config
        address aaveAddressesProvider; // 20B
        uint64 minBTCAmt; // 8B  | same range as maxBTCAmt
        uint16 preClosureFeeBps; // 2B  | max < 10,000
        uint16 liquidationFee; // 2B  | max 2,000
        // ── Slot 2 (28B used, 4B spare): Bitmor pool + slippage + loan config
        address bitmorPool; // 20B
        uint16 slippageSharesToAsset; // 2B  | max < 10,000
        uint16 slippageSwap; // 2B  | max < 10,000
        uint16 minDeposit; // 2B  | max < 10,000
        uint16 maxDuration; // 2B  | months
        // ── Slots 3–7: Remaining addresses (12B spare each, no params to pack)
        address oracle;
        address collateralAsset;
        address debtAsset;
        address btc;
        address bitmorAddressesProvider;
        // ── Mappings (each starts at its own keccak slot)
        mapping(address => DataTypes.LoanData) loansByLSA;
        mapping(address => uint256) userLoanCount;
        mapping(address => mapping(uint256 => address)) userLoanAtIndex;
    }

    function _getLoanStorage() internal pure returns (LoanStorageData storage $) {
        assembly {
            $.slot := LOAN_STORAGE_LOCATION
        }
    }
}
