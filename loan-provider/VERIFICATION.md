# Contract Verification Guide

## Sourcify Verification

The verification script (`script/verification/VerifyAllContracts.s.sol`) now uses **Sourcify** for contract verification.

### Advantages of Sourcify

- **No API keys required** - Sourcify is open-source and free to use
- **Automatic constructor detection** - No need to manually encode constructor arguments
- **Decentralized verification** - Contracts are verified on IPFS
- **Multi-chain support** - Works across all EVM chains

### Prerequisites

**No environment variables or API keys required!** Sourcify verification works out of the box.

### Usage

To verify all deployed contracts on Sourcify:

```bash
make verifyAll
```

Or run directly:

```bash
forge script script/verification/VerifyAllContracts.s.sol:VerifyAllContracts \
  --rpc-url base_sepolia \
  --ffi
```

Example output:
```
Verifying contracts for chain ID: 84532
=================================
Verifying contract: UniswapV4SwapAdapterWrapper
Address: 0x204fC5AD7D18b2fcBE86959A30A81ca28F831262
[SUCCESS] Successfully verified: UniswapV4SwapAdapterWrapper
=================================
```

### What Gets Verified

The script verifies all contracts listed in `deployments.json`:
1. UniswapV4SwapAdapterWrapper
2. LoanVault
3. Loan
4. LoanVaultFactory

### Verification Results

After running the script, check verification status:

- **Sourcify Repository**: https://repo.sourcify.dev/
- **Base Sepolia Explorer**: https://sepolia.basescan.org/
- **Base Mainnet Explorer**: https://basescan.org/

Verified contracts on Sourcify will show a checkmark on BaseScan and other block explorers.

### How It Works

1. Script reads deployed contract addresses from `deployments.json`
2. For each contract, it executes `forge verify-contract` with:
   - Contract address (e.g., `0x204fC5AD7D18b2fcBE86959A30A81ca28F831262`)
   - Contract path (e.g., `src/protocol/Loan.sol:Loan`)
   - Chain ID (e.g., `84532` for Base Sepolia)
   - Verifier: `sourcify`
3. Sourcify automatically:
   - Fetches the deployed bytecode from the blockchain
   - Compiles your source code locally
   - Extracts constructor arguments from the deployed bytecode
   - Compares the compiled bytecode with the deployed bytecode
4. If matching, Sourcify:
   - Publishes the verified source code to IPFS
   - Notifies block explorers (BaseScan, etc.)
   - Makes the source code publicly available

### Command Structure

The script generates commands in this format:
```bash
forge verify-contract <ADDRESS> <CONTRACT_PATH> \
  --chain-id <CHAIN_ID> \
  --verifier sourcify
```

Example:
```bash
forge verify-contract 0x204fC5AD7D18b2fcBE86959A30A81ca28F831262 \
  src/adapters/UniswapV4SwapAdapterWrapper.sol:UniswapV4SwapAdapterWrapper \
  --chain-id 84532 \
  --verifier sourcify
```

### Troubleshooting

**Verification fails:**
- Check that contracts are actually deployed to the addresses in `deployments.json`
- Ensure compiler settings in `foundry.toml` match deployment settings
  - `optimizer = true`
  - `optimizer_runs = 200`
- Verify you're on the correct network (check `block.chainid`)
- Ensure the contract source code hasn't changed since deployment

**"FFI not enabled" error:**
- Ensure FFI is enabled in `foundry.toml`: `ffi = true`

**Already verified:**
- If a contract is already verified, Sourcify will skip it automatically
- This is normal behavior and not an error
