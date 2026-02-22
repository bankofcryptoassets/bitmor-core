---
title: Untitled
date: 2026-02-22
---

1. **Loan contract**
    
    1. Only executor can update insuranceID
    2. Only executor can initialize loan
    3. Only Loan contract can supply bvBTC shares (i\_COLLATERAL\_ASSET) and borrow USDC from BLP on behalf of LSAs
    4. loanData can only be updated by Loan contract or lending pool through collateral manager on both type of liquidation
    5. Only borrower can close the loan
    6. bvBTC shares cannot be borrowed by anybody in the BLP
    7. Only USDC Vault and Loan contract can make deposits into the lending pools
    8. initializeLoan on same LoanVault must revert, only one loan per LoanVault
2. **Closed and liquidated loans**
    
    1. _If loanData.status ∈ {Completed, Liquidated}:_
        
        1. *getVDTTokenAmount(bitmorPool, debtAsset, lsa) == 0*
        2. *getATokenAmount(bitmorPool, collateralAsset, lsa) == 0*
        3. Cannot be repaid
        4. Can NEVER transition back to Active
    2. Close Loan Redeems Full BTC to Borrower
        
        1. On closeLoan:
            
            1. _USDC received by borrower == LSA.bvBTC\_shares × bvBTC.pricePerShare_
            2. _LSA.bvBTC\_shares after == 0_
    3. Borrower can pay their remaining debt \[*(getVDTTokenAmount(bitmorPool, debtAsset, lsa)*\] at any time and close the loan. BTC or USDC is sent to the borrower based on their choice.
3. **Repayment**
    
    1. repayments reduce outstanding debt, they can never increase it
    2. Monthly repayment must never Exceeds Remaining Debt
        
        1. *finalAmountRepaid* = min(estimatedMonthlyPayment, getVDTTokenAmount(bitmorPool, debtAsset, lsa))
    3. Repayment Strictly Reduces Real Debt
    4. Repayment increases pool liquidity
        
        1. _BLP.available\_liquidity\_after == BLP.available\_liquidity\_before + finalAmountRepaid_
    5. Due Date Advances by Exactly 30 days (*LOAN\_REPAYMENT\_INTERVAL*) after a monthly repayment
    6. Excess repayment is applied to future principal payment
    7. Last payment
        
        1. _debt\_remaining after payment == 0, shouldn’t be negative_
        2. *finalAmountRepaid== getVDTTokenAmount(bitmorPool, debtAsset, lsa) (before repayment)*
    8. _If amount< estimatedMonthlyPayment_
        
        1. Due date does NOT advance
        2. _debt\_remaining_ decreases by payment
        3. multiple partial payments can convert to full monthly payment if the amount is correct
4. **Micro-Liquidations and Full-Liquidations**
    
    1. Missed payments cannot trigger liquidation or micro-liquidation before _lastPaymentTimestamp + LOAN\_REPAYMENT\_INTERVAL + s\_gracePeriod_
    2. Insured loans cannot be fully price-liquidated
    3. A loan that is current (not past due) must not be liquidatable via non-payment path if there is insurance
        
        1. *If lastPaymentTimestamp ≥ (previous lastPaymentTimestamp + LOAN_REPAYMENT_INTERVAL):*
            
            1. non-payment micro-liquidation MUST revert
            2. non-payment full-liquidation MUST revert
    4. Micro-liquidation only triggerable if payment missed and grace period expired
    5. A second micro-liquidation cannot occur until next\_payment\_due + grace period is crossed
    6. Micro-liquidation sells exactly one monthly payment worth + liquidator bonus
        
        1. _debtToCover = estimatedMonthlyPayment (capped at VDT balance)_
        2. *sold_btc = cash_needed / price Actual BTC sold == sold_btc (± 1 wei rounding)*
    7. Micro-liquidation must pass post-sale guard or escalate to full liquidation
        
        1. *(getATokenAmount(lsa) - collateralToSeize) × collateralPriceUSD*
        2. *totalDebtAfter = getVDTTokenAmount(lsa) - debtToCover*
        3. _post\_sale\_guard =» remaining collateral value ≥ remaining debt + bonus threshold_
        4. *LIQUIDATION_BONUS_BPS is the multiplier (10500 = 105%)*
        5. _If post\_sale\_guard == false :- micro-liquidation MUST trigger full liquidation_
    8. Micro liquidations state update
        
        1. _USDC debt decreases by debtToCover (= estimatedMonthlyPayment)_
        2. _loanData.duration decreases by 1 month_
        3. _loanData.status remains Active(not liquidated_)
        4. loanData.lastPaymentTimestamp = block.timestamp
    9. If BTC available in collateral is not enough to cover the liquidator, insurance must be sold and sent to liquidator
    10. Full liquidation condition:
        
        1. *If getATokenAmount(lsa) × collateralPriceUSD ≥ getVDTTokenAmount(lsa) × (1 +LIQUIDATION_BONUS_BPS/10000) // healthy*
            
            *AND (block.timestamp ≤ lastPaymentTimestamp + LOAN_REPAYMENT_INTERVAL + s_gracePeriod) // current on payments*
            
            _THEN liquidate() MUST revert_
        2. _If full liquidation succeeds, loanData.status == DataTypes.LoanStatus.Liquidated_
    11. Full Liquidation fund distribution
        
        1. *Proceeds = collateral seized and sold (bvBTC redeemed to cbBTC)+ insurance_sale_value (if applicable)*
        2. *Step 1: pool receives min(getVDTTokenAmount(bitmorPool, debtAsset, lsa), total liquidation proceeds)*
        3. *Step 2: liquidator receives min(bonus-s_liquidationFee, proceeds - pool_payment)*
        4. _Step 3: Protocol receives s\_liquidationFee + insurance amount still remaining after all payments_
        5. Insurance payment is off-chain, hence on chain verification is difficult
    12. Liquidator never receives greater than specified
        
        1. *Full: bonus_full = (LIQUIDATION_BONUS_BPS - 10000) / 10000 × debtToCover - s_liquidationFee portion*
        2. _Micro: bonus\_micro = liquidation bonus × estimatedMonthlyPayment- protocol\_fee_
    13. Lender Capital protection
        
        1. *USDC returned to pool ≥ min(VDT balance, collateral sale proceeds + insurance proceeds)*
        2. _collateral sale proceeds+ insurance proceeds ≥ VDT balance + bonus, or protocol holds bad debt_
        3. Insurance payment is off-chain, hence on chain verification is difficult
5. **USDC Vault**
    
    1. Anybody can deposit USDC in this vault
    2. USDC vault can be rebalanced by the USDC Vault allocator, allocation happens based on the target set for Aave. No manual configuration like BTC Vault.
    3. User must be able to withdraw funds from vault if available in either of BLP or Aave, only borrowed out funds are unavailable
        
        1. *maxWithdraw(owner)* *=USDC balance in BLP's aToken contract + Aave aUSDC held by USDCStrategy (redeemable)*
        2. _withdrawal must succeed if amount ≤ maxWithdraw(owner)_
        3. _withdrawal must revert if amount > maxWithdraw(owner)_
    4. *usdcVault.totalAssets() == ERC20(i_asset).balanceOf(address(vault)) + s_strategy.totalAssets()*
    5. _usdcVault.totalSupply() == Σ bvUSDC.balanceOf(addr)_
    6. aUSDC balance tracked in vault == actual aUSDC held
    7. No value extraction from deposit→withdraw roundtrip
        
        1. I_f user deposits X USDC and immediately withdraws (no intervening borrows)_
        2. *user receives ≥ X - 1 wei (rounding tolerance)*
    8. Rebalance does not change total assets
        
        1. _bvUSDC.totalAssets() before reallocateAssets() == bvUSDC.totalAssets() after reallocateAssets()_
6. **BTC Vault**
    
    1. BTC vault can only accept BTC deposit from Loan contract
    2. Only the BTC Vault allocator (role BVA\_FAST) can call reallocateFunds() in BTC vault
    3. Only Curator (role BVC) can set DataTypes.Strategy.cap and add or remove strategies
    4. On close loan BTC must be withdrawn from strategy and given to user
    5. On liquidation and micro-liquidation BTC must be withdrawn from strategy and given to Liquidator
    6. Total BTC balance consistency
        
        1. _getAssetInStrategy(strategy) ≤ strategies\[strategyIndex\].cap_
        2. _Σ getAssetInStrategy(strategy\_i) == btcVault.totalAssets()_
        3. _btcVault.totalAssets() ≥ Σ getAssetInStrategy(strategy\_i)_
    7. BTC can be Withdrawn Only on Close or Liquidation
        
        1. _bvBTC.redeem() or bvBTC.withdraw() can only be called_
            
            1. _During closeLoan (BTC goes to borrower)_
            2. *During liquidation (BTC goes to liquidator / is sold)*
            3. _BTC can leave the vault only into strategies apart from this_
            4. _Access restricted by role BVD_
    8. Share-to-Asset Ratio Consistency
        
        1. *btcVault.totalSupply() * btcVault.convertToAssets(1e8) / 1e8 == btcVault.totalAssets()*
    9. No Inflation attack
        
        1. A first depositor depositing X BTC must receive shares proportional to X
        2. A second depositor cannot manipulate share price to steal from the first
    10. There must be no silent loss during withdrawal from a strategy
        
        1. *BTC received from strategy ≥ shares_burned × previewRedeem(shares) - s_slippage_sharesToAsset*
7. Lending Pool
    
    1. Borrow Index Never Decreases
    2. Liquidity Index Never Decreases
    3. scaledBalanceOf(lsa) Only Decreases After Origination. Interest growth is captured entirely by the borrow index, NOT by *scaled\_debt* inflation.
    4. USDC borrowed cannot be greater than what was deposited in BLP
        
        1. *variableDebtToken.totalSupply() ≤ IERC20(usdc).balanceOf(aTokenAddress)*
    5. USDC borrow rate must be calculated based on all available USDC liquidity including that of Aave
        
        1. *utilizationRate = totalDebt.rayDiv(availableLiquidity + totalDebt)*
        2. *currentVariableBorrowRate ∈ [_baseVariableBorrowRate, baseVariableBorrowRate + variableRateSlope1 + _variableRateSlope2]*
        3. Rate must Monotonically Increases with Utilization
            
            1. _If utilization\_a > utilization\_b: rate(utilization\_a) ≥ rate(utilization\_b_
8. **Accounting**
    
    1. Global USDC Conservation:
        
        1. *aToken.totalSupply() == variableDebtToken.totalSupply() + total_idle_USDC (IERC20(usdc).balanceOf(aTokenAddress) + aUSDC held by USDCStrategy) + protocol_revenue_accrued (if protocol fee exists)*
    2. Global BTC Conservation:
        
        1. _btcVault.totalAssets() == Σ previewRedeem(getATokenAmount(lsa\_i)) for all active loans_
    3. No Value Leakage Across protocol:
        
        1. *value_in(BLP) + value_in(bvUSDC_aave) + value_in(bvBTC) + value_in(all_LSAs) == Σ LP_deposits - Σ LP_withdrawals + Σ borrower_deposits - Σ borrower_BTC_withdrawals + Σ interest_accrued - Σ interest_paid_to_LPs*
    4. Post initialization Invariants:
        
        1. *getVDTTokenAmount(bitmorPool, debtAsset, lsa) == loanData.loanAmount (at origination, ± 1 wei)*
        2. *btcVault.previewRedeem(getATokenAmount(lsa)) ≈ swap_output(loanData.loanAmount + loanData.depositAmount)*
        3. *IERC20(i_DEBT_ASSET).balanceOf(lsa) == 0 (no leftover USDC in the LSA)*
        4. *IERC20(i_DEBT_ASSET).balanceOf(address(loan)) change == 0 (Loan contract doesn't keep any USDC)*
    5. Aggregate Scaled Debt must be consistent
        
        1. _variableDebtToken.totalSupply() == Σ getVDTTokenAmount(lsa\_i) for all active LSAs_
9. **Others**
    
    1. At 100% maximum utilization
        
        1. LP withdrawals revert (insufficient liquidity, No liquidity in Aave either)
        2. New borrows revert (insufficient liquidity)
        3. Repayments still succeed (they add liquidity)
    2. Single-Wei Operations Deposits, repayments, and withdrawals of 1 wei must either
        
        1. Succeed with correct accounting OR Revert with a minimum amount check
        2. They must NEVER succeed while losing the 1 wei to rounding
    3. Maximum Value Operations: Operations with type(uint256).max must either
        
        1. Revert cleanly (overflow protection) OR Be bounded to a sensible maximum
        2. They must NEVER overflow silently