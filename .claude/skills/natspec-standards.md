---
name: natspec-standard
description: Use when adding, editing, or reviewing comments in Solidity (.sol) files. Triggers on documentation requests, code commenting, forge doc generation, or contract API documentation.
---

# NatSpec Documentation Standard

## Overview

NatSpec (Ethereum Natural Language Specification) provides structured documentation for Solidity contracts. Comments are parsed by `forge doc` for auto-generated documentation and displayed on Etherscan.

## When to Use

- Adding comments to any `.sol` file
- Documenting public/external functions, state variables, errors, events, structs
- Reviewing code for documentation completeness
- Preparing contracts for `forge doc` generation
- Writing interface documentation

## Quick Reference

| Tag           | Required For            | Description                                        |
| ------------- | ----------------------- | -------------------------------------------------- |
| `@title`      | Contracts/Interfaces    | Contract title                                     |
| `@author`     | Contracts               | Author name                                        |
| `@notice`     | All public items        | User-facing description                            |
| `@dev`        | Complex logic           | Technical implementation details                   |
| `@param`      | Functions/Errors/Events | Document each parameter (in order)                 |
| `@return`     | Functions               | Document each return value                         |
| `@inheritdoc` | Overrides               | Copy docs from parent (e.g., `@inheritdoc IERC20`) |
| `@custom:*`   | Protocol-specific       | Custom tags (security, access, oz-upgrades)        |

## Tag Order

Always use this order for consistency:

1. `@notice` - User-facing description
2. `@dev` - Technical details (if needed)
3. `@param` - Parameters in function signature order
4. `@return` - Return values in order
5. `@custom:*` - Custom tags last

## Contract-Level Documentation

```solidity
/**
 * @title Loan
 * @author Protocol Name
 * @notice Main entry point for BTC-collateralized loan operations
 * @dev Uses Aave V3 flash loans and Uniswap V4 for swaps
 * @custom:security Uses AccessManaged for role-based access control
 */
contract Loan is ILoan, AccessManaged {}
```

## Function Documentation

### Full Format (complex functions)

```solidity
/**
 * @notice Initializes a new loan with flash loan funding
 * @dev Executes flash loan -> swap -> collateral deposit flow
 * @param deposit User's USDC down payment amount
 * @param premium Total premium over loan duration
 * @param btcAmount Target cbBTC collateral amount
 * @param duration Loan duration in months (1-60)
 * @param data Additional swap parameters
 * @return lsa Address of the created LoanVault
 * @custom:access Requires LOAN_INITIALIZER_ROLE
 */
function initializeLoan(
    uint256 deposit,
    uint256 premium,
    uint256 btcAmount,
    uint256 duration,
    bytes calldata data
) external returns (address lsa);
```

### Inline Format (simple functions)

For simple functions, document params inline using backticks:

```solidity
/// @notice Returns the sum of `a` and `b`.
function add(uint256 a, uint256 b) external pure returns (uint256);

/// @notice Transfers `amount` tokens to `recipient`.
function transfer(address recipient, uint256 amount) external returns (bool);
```

## Error Documentation

```solidity
/**
 * @notice Thrown when loan duration exceeds maximum allowed
 * @param provided The duration provided by user
 * @param maximum The maximum allowed duration
 */
error Loan__InvalidDuration(uint256 provided, uint256 maximum);
```

## Event Documentation

```solidity
/**
 * @notice Emitted when a new loan is initialized
 * @param borrower Address of the loan borrower
 * @param lsa Address of the created LoanVault
 * @param btcAmount Amount of cbBTC collateral
 * @param duration Loan duration in months
 */
event LoanInitialized(
    address indexed borrower,
    address indexed lsa,
    uint256 btcAmount,
    uint256 duration
);
```

## Struct Documentation

```solidity
/**
 * @notice Data structure for loan information
 * @dev Stored in LoanStorage mapping
 */
struct LoanData {
    /// @dev Address of the loan borrower
    address borrower;
    /// @dev Amount of collateral in cbBTC (8 decimals)
    uint256 btcAmount;
    /// @dev Monthly payment amount in USDC (6 decimals)
    uint256 monthlyPayment;
    /// @dev Loan start timestamp
    uint256 startTime;
    /// @dev Current loan status
    LoanStatus status;
}
```

## Custom Tags

| Tag                    | Usage                                   |
| ---------------------- | --------------------------------------- |
| `@custom:security`     | Security considerations and audit notes |
| `@custom:access`       | Access control requirements             |
| `@custom:oz-upgrades`  | OpenZeppelin upgrade safety annotations |
| `@custom:experimental` | Experimental features                   |

## Common Mistakes

| Mistake                                 | Fix                                                      |
| --------------------------------------- | -------------------------------------------------------- |
| Missing backticks around variable names | Use `` `amount` `` not `amount` in @notice/@dev          |
| Parameters not in signature order       | Match `@param` order to function signature               |
| Skipping `@inheritdoc` for overrides    | Use `@inheritdoc ContractName` to avoid duplication      |
| Empty `@dev` tags                       | Only add `@dev` when there's technical detail to explain |
| Outdated comments                       | Update NatSpec whenever function behavior changes        |

## Review Checklist

When reviewing Solidity code for documentation:

- [ ] All public/external functions have `@notice`
- [ ] All parameters have `@param` tags (or inline docs for simple functions)
- [ ] All return values have `@return` tags
- [ ] Complex logic has `@dev` explanations
- [ ] Custom errors include `@param` for error values
- [ ] Events document all parameters
- [ ] Structs document all fields
- [ ] Security-critical functions have `@custom:security`
- [ ] Access-controlled functions have `@custom:access`
- [ ] Variable names use backticks in `@notice`/`@dev`
