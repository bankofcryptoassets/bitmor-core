---
name: natspec-standards
description: NatSpec documentation standards for Solidity in Bitmor Protocol
allowed-tools:
  - Read
  - Grep
---

All public/external functions and state variables must have NatSpec comments.

## Required Tags

| Tag | Required For | Description |
|-----|--------------|-------------|
| `@notice` | All public items | User-facing description |
| `@dev` | Complex logic | Technical implementation details |
| `@param` | Functions | Each parameter documented |
| `@return` | Functions | Each return value documented |
| `@inheritdoc` | Overrides | Reference parent contract |

## Contract-Level Documentation

```solidity
/// @title Loan
/// @author Bitmor Protocol
/// @notice Main entry point for BTC-collateralized loan operations
/// @dev Uses Aave V3 flash loans and Uniswap V4 for swaps
/// @custom:security Uses AccessManaged for role-based access control
contract Loan is ILoan, AccessManaged, Pausable {
```

## Function Documentation

### Standard Format
```solidity
/// @notice Initializes a new loan with flash loan funding
/// @dev Executes flash loan -> swap -> collateral deposit flow
/// @param deposit User's USDC down payment amount
/// @param premium Total premium to be paid over loan duration
/// @param collateralAmount Target cbBTC collateral amount
/// @param duration Loan duration in months (1-60)
/// @param data Additional swap parameters for Uniswap V4
/// @return lsa Address of the created LoanVault (Loan Smart Account)
/// @custom:access Requires LOAN_INITIALIZER_ROLE
function initializeLoan(
    uint256 deposit,
    uint256 premium,
    uint256 collateralAmount,
    uint256 duration,
    bytes calldata data
) external returns (address lsa);
```

### Simple Functions
For simple functions, inline parameter documentation is acceptable:

```solidity
/// @notice Returns the sum of `a` and `b`.
function add(uint256 a, uint256 b) external pure returns (uint256);
```

## Custom Tags Used in Bitmor

| Tag | Usage |
|-----|-------|
| `@custom:security` | Security considerations and audit notes |
| `@custom:access` | Access control requirements |
| `@custom:oz-upgrades` | OpenZeppelin upgrade safety annotations |

## Error Documentation

```solidity
/// @notice Thrown when loan duration exceeds maximum allowed
/// @param provided The duration provided by user
/// @param maximum The maximum allowed duration
error Loan__InvalidDuration(uint256 provided, uint256 maximum);
```

## Event Documentation

```solidity
/// @notice Emitted when a new loan is initialized
/// @param borrower Address of the loan borrower
/// @param lsa Address of the created LoanVault
/// @param collateralAmount Amount of cbBTC collateral
/// @param duration Loan duration in months
event LoanInitialized(
    address indexed borrower,
    address indexed lsa,
    uint256 collateralAmount,
    uint256 duration
);
```

## Struct Documentation

```solidity
/// @notice Data structure for loan information
/// @dev Stored in LoanStorage mapping
struct LoanData {
    /// @dev Address of the loan borrower
    address borrower;
    /// @dev Amount of collateral in cbBTC (8 decimals)
    uint256 collateralAmount;
    /// @dev Monthly payment amount in USDC (6 decimals)
    uint256 monthlyPayment;
    /// @dev Loan start timestamp
    uint256 startTime;
    /// @dev Current loan status
    LoanStatus status;
}
```

## Review Checklist

- [ ] All public/external functions have `@notice`
- [ ] All parameters have `@param` tags
- [ ] All return values have `@return` tags
- [ ] Complex logic has `@dev` explanations
- [ ] Custom errors include `@param` for error values
- [ ] Events document all parameters
- [ ] Structs document all fields
- [ ] Security-critical functions have `@custom:security`
- [ ] Access-controlled functions have `@custom:access`
