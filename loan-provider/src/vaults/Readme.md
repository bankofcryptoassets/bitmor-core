# Bitmor Vaults

Bitmor Protocol consists of two vaults acting as reserve for Bitmor Lending Pool (BLP).

## BTC Vault

Bitmor BTC Vault (symbol: `bvBTC`), is a ERC4626 compliant vault with Tokenized Strategies. 
The BTC swapped while `initializingLoan` on Bitmor, gets deposited into this vault and utilized to generate yield on them instead of staying idle in the BLP as borrowing for `BTC` is NOT ALLOWED.

The BTC Vault is managed by **Access Manager**, the following are the roles, their corresponding functions and expected delay for each role:

| Role Label                         | RoleId | Role                                               | Contract  | Function                                       | Expected Delay | Type                     |
| ---------------------------------- | ------ | -------------------------------------------------- | --------- | ---------------------------------------------- | -------------- | ------------------------ |
| **BVM_FAST** (BTC Vault Manager)   | 11     | Pause, emergency withdraw                          | BTC Vault | pause, emergencyWithdraw                       | 0              | Multisig                 |
| **BVM_SLOW** (BTC Vault Manager)   | 110    | Set fee recipient and unpause contract             | BTC Vault | setFeeRecipient, unpause                       | 1 DAY          | Multisig                 |
| **BVC** (BTC Vault Curator)        | 12     | Change strategy cap, add strategy, remove strategy | BTC Vault | addStrategy, removeStrategy, changeStrategyCap | 1 DAY          | Multisig                 |
| **BVA_SLOW** (BTC Vault Allocator) | 130    | Set supply queue, set withdraw queue               | BTC Vault | setSupplyQueue, setWithdrawQueue               | 1 DAY          | TBD                      |
| **BVA_FAST** (BTC Vault Allocator) | 13     | Reallocate assets                                  | BTC Vault | reallocateAssets                               | 0              | TBD                      |
| **BVD** (BTC Vault Depositor)      | 14     | Deposit assets in vault.                           | BTC Vault | deposit                                        | 0              | Contract (Loan Provider) |

### Asset
The only asset acceptable in Bitmor BTC Vault is **cbBTC**.

> NOTE: ONLY **BLP** is allowed to deposit assets in the vault on behalf of the user.

### Shares
On despositing assets, `bvBTC` shares are minted to the supplied address. These shares are used as underlying reserve token in the BLP.

### Strategies
Bitmor BTC Vault works with Tokenized Strategies. Every strategy have the same underlying asset as the vault and can have a single yield source. 

- Every strategy is allocated a `cap` which is the maximum amount of assets that can be deposited into the strategy.
- The assets received in strategy are allocated to the yield source to generate yield on them.

## USDC Vault

Bitmor USDC Vault (symbol: `bvUSDC`), is a ERC4626 compliant vault. This vault is used for accepting **USDC** from *lenders*. 

The USDC received from the lenders are deposited into `SimpleStrategy` which deposit them between different yield sources, one of them is ALWAYS BLP.

The deposited assets in BLP act as reserve for the BLP from where the user creating loan can borrow USDC. 

The USDC Vault is managed by the **Access Manager**, the following are the roles, their corresponding functions and expected delay for each role:

| Role Label                        | RoleId | Role                                                                | Contract   | Function                                                             | Expected Delay | Type     |
| --------------------------------- | ------ | ------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------- | -------------- | -------- |
| **UVM_FAST** (USDC Vault Manager) | 21     | Pause, withdraw all funds from yield source                         | USDC Vault | pause, withdrawAllFunds                                              | 0              | Multisig |
| **UVM_SLOW** (USDC Vault Manager) | 210    | Unpause contract                                                    | USDC Vault | unpause                                                              | 1 DAY          | Multisig |
| **UVC** (USDC Vault Curator)      | 22     | Set strategy, update external allocation, update minimum delta | USDC Vault | setStrategy, updateMinimumDeltaRequired, updateExternalAllocation | 1 DAY          | Multisig |
| **UVA** (USDC Vault Allocator)    | 23     | Reallocate assets                                                   | USDC Vault | reallocateAssets                                                     | 0              | TBD      |

### Asset
The only asset acceptable in Bitmor USDC Vault is **USDC**. The total assets supplied in the vault act as the reserve supply in USDC reserve to maintain the utilization ratio.

### Shares
On depositing assets, `bvUSDC` shares are minted to the supplied address.

### Strategy
Bitmor USDC Vault work with `SimpleStrategy` which distributed the receievd assets among two yield source of which one needs to BLP. 

- Whenever BLP gets a request to withdraw assets more than its current balance in the reserve, it reallocates the funds in the strategy such that it can fulfill the withdraw request and maintain the supply ratio among yield sources in the strategy.
