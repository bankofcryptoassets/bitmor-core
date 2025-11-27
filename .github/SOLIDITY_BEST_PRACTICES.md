# Solidity Best Practices for Git Repository Hygiene

## Code Quality & Security

### 1. Static Analysis Integration
```yaml
# Already included in your CI
- name: Run Slither analysis
  run: slither . --exclude-dependencies
```

**Additional tools to consider:**
- **Mythril**: `pip install mythril && myth analyze contracts/`
- **Echidna**: Fuzzing tool for property-based testing
- **Semgrep**: Pattern-based static analysis

### 2. Code Formatting Standards
```bash
# Enforce consistent formatting
forge fmt --check  # In CI
forge fmt          # Before commits
```

**Foundry.toml configuration:**
```toml
[fmt]
line_length = 100
tab_width = 4
bracket_spacing = true
int_types = "short"
multiline_func_header = "all"
quote_style = "double"
number_underscore = "thousands"
single_line_statement_blocks = "preserve"
```

### 3. Gas Optimization
```bash
# Generate gas reports
forge test --gas-report
forge test --gas-report > gas-report.txt
```

**Gas-efficient patterns:**
- Use `uint256` instead of smaller uints when possible
- Pack structs efficiently
- Use `calldata` instead of `memory` for read-only function parameters
- Implement proper access control to prevent unnecessary external calls

## Testing & Coverage

### 4. Comprehensive Testing Strategy
```solidity
// Test structure example
contract LoanTest is Test {
    // Unit tests
    function testLoanCreation() public { }
    function testLoanRepayment() public { }

    // Integration tests
    function testLoanWithVault() public { }

    // Fuzz tests
    function testFuzzLoanAmount(uint256 amount) public { }

    // Invariant tests
    function invariant_totalSupplyEqualsSumOfBalances() public { }
}
```

**Coverage requirements:**
```bash
# Minimum 80% line coverage
forge coverage --report lcov
```

### 5. Test Organization
```
test/
├── unit/           # Unit tests for individual contracts
├── integration/    # Cross-contract interaction tests
├── fuzz/          # Property-based fuzzing tests
├── invariant/     # Invariant testing
└── mocks/         # Mock contracts for testing
```

## Documentation Standards

### 6. NatSpec Documentation
```solidity
/**
 * @title Loan Contract
 * @author Bitmor Team
 * @notice Manages individual loans with collateral
 * @dev Implements EIP-4626 vault standard for tokenization
 */
contract Loan {
    /**
     * @notice Creates a new loan with specified parameters
     * @param borrower Address of the borrower
     * @param amount Loan amount in base currency
     * @param collateralToken Address of collateral token
     * @return loanId Unique identifier for the created loan
     * @dev Emits LoanCreated event upon successful creation
     */
    function createLoan(
        address borrower,
        uint256 amount,
        address collateralToken
    ) external returns (uint256 loanId) {
        // Implementation
    }
}
```

## Git Workflow Hygiene

### 7. Pre-commit Hooks
Create `.github/pre-commit-config.yaml`:
```yaml
repos:
  - repo: local
    hooks:
      - id: forge-fmt
        name: Forge format check
        entry: forge fmt --check
        language: system
        types: [solidity]
        pass_filenames: false

      - id: forge-build
        name: Forge build
        entry: forge build
        language: system
        pass_filenames: false

      - id: slither-check
        name: Slither security analysis
        entry: slither . --exclude-dependencies
        language: system
        pass_filenames: false
```

### 8. Commit Message Standards
```
feat(loan): add loan creation functionality
fix(vault): resolve vault share calculation bug
test(integration): add cross-contract interaction tests
docs(readme): update deployment instructions
refactor(core): optimize gas usage in loan repayment
security(access): implement role-based access control
```

**Conventional Commits format:**
- `feat`: New features
- `fix`: Bug fixes
- `test`: Test additions/modifications
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `security`: Security improvements
- `chore`: Maintenance tasks

### 9. File Structure Standards
```
loan-provider/
├── src/
│   ├── interfaces/     # Contract interfaces
│   ├── libraries/      # Shared logic libraries
│   ├── loan/          # Core loan contracts
│   ├── vault/         # Vault-related contracts
│   ├── dependencies/  # External dependencies
│   └── mocks/         # Mock contracts for testing
├── test/
├── script/           # Deployment scripts
├── docs/            # Technical documentation
└── audits/          # Security audit reports
```

### 10. Security Review Checklist

**Before each PR:**
- [ ] All tests pass (`forge test`)
- [ ] Static analysis clean (`slither .`)
- [ ] Gas optimization reviewed
- [ ] Access controls implemented
- [ ] Input validation present
- [ ] Reentrancy guards where needed
- [ ] Integer overflow protection
- [ ] External call safety measures

**For major changes:**
- [ ] External security audit scheduled
- [ ] Formal verification considered
- [ ] Economic attack vectors analyzed
- [ ] Upgrade path documented (if applicable)

## Continuous Integration Enhancements

### 11. Advanced CI Checks
```yaml
# Add to your workflow
- name: Check contract size
  run: |
    forge build --sizes
    # Fail if any contract exceeds 24KB limit

- name: Verify no hardcoded addresses
  run: |
    grep -r "0x[0-9a-fA-F]\{40\}" src/ && exit 1 || exit 0

- name: Check for TODO/FIXME comments
  run: |
    grep -r "TODO\|FIXME" src/ && exit 1 || exit 0
```

### 12. Deployment Safety
```solidity
// Use CREATE2 for deterministic addresses
// Implement proper initialization patterns
// Use proxy patterns for upgradability when needed

contract LoanVaultFactory {
    function deployVault(bytes32 salt) external returns (address) {
        return Clones.cloneDeterministic(vaultImplementation, salt);
    }
}
```

## Monitoring & Maintenance

### 13. Dependency Management
```bash
# Regularly update dependencies
forge update

# Audit dependency changes
git diff lib/

# Pin to specific versions for production
```

### 14. Performance Monitoring
- Track gas costs over time
- Monitor contract size growth
- Benchmark critical functions
- Set up alerts for unusual patterns

## Implementation Priority

1. **Immediate (Week 1)**:
   - Set up branch protection rules
   - Configure pre-commit hooks
   - Establish commit message standards

2. **Short-term (Month 1)**:
   - Implement comprehensive testing strategy
   - Add static analysis to CI
   - Create documentation standards

3. **Long-term (Quarter 1)**:
   - External security audits
   - Formal verification for critical components
   - Advanced monitoring and alerting
