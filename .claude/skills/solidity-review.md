---
name: solidity-review
description: Solidity smart contract review guidelines for security and best practices
allowed-tools:
  - Read
  - Grep
  - Glob
---

When reviewing Solidity code, focus on:

## Security Checks

### Reentrancy Vulnerabilities
- Check for external calls before state updates (CEI pattern)
- Look for `call`, `send`, `transfer` followed by state changes
- Verify `ReentrancyGuard` usage on vulnerable functions

### Integer Overflow/Underflow
- Solidity 0.8+ has built-in checks, but verify unchecked blocks
- Review custom math operations in `unchecked {}` blocks

### Access Control Issues
- Verify `onlyOwner`, `restricted`, or role-based modifiers
- Check for missing access control on sensitive functions
- Validate `AccessManaged` pattern usage

### Flash Loan Attack Vectors
- Review price oracle manipulation risks
- Check for atomic transaction vulnerabilities
- Verify Aave V3 flash loan callback security

### External Call Safety
- Validate return values from external calls
- Check for proper error handling on `call` operations
- Verify address validation before external calls

## Code Quality

### Error Handling
- Use custom errors instead of `require` strings
- Define errors in `Errors.sol` library
- Include relevant parameters in error definitions

### Events
- Emit events for all state changes
- Include indexed parameters for filtering
- Event names should be past-tense (e.g., `LoanInitialized`)

### Storage Optimization
- Pack structs efficiently (same-sized types together)
- Use `uint256` for single values, smaller types for struct packing
- Avoid unnecessary storage reads in loops

## Bitmor-Specific Patterns

### Loan Flow Verification
1. Flash loan from Aave V3
2. Swap USDC → cbBTC via Uniswap V4
3. Deposit collateral to Bitmor Lending Pool
4. Create LoanVault (LSA) for user
5. Repay flash loan

### LoanVault (LSA) Checks
- Verify CREATE2 address consistency
- Check deterministic deployment via factory
- Validate proxy pattern implementation

### Integration Verification
- Aave V3 Pool interactions
- Uniswap V4 swap adapter usage
- Chainlink oracle price feeds
