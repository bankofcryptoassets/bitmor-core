# Bitmor Lending Pool

This repository contains the smart contracts for Bitmor Lending Pool. This repo is a fork of Aave V2, with a custom liquidation mechanism introducing `microLiquidationCall` and custom health-factor management depending on the type of **Loan** user took, i.e., insured or uninsured loan.

The repository uses Docker Compose and Hardhat as development enviroment for compilation, testing and deployment tasks.

## New Features with respect to AAVE V2

### Micro Liquidation Call

When a liquidator initializes a `microLiquidationCall`, if the checks passes, then its sell user's collateral just enough to get them again in the good health factor and to pay the liquidation bonus. The doesn't liquidates user's complete position and maintain healthy protocol economics.

### Full Liquidation Call

When a liquidator intializes a `liquidationCall`, if the check passess, then its does the liquidation same as how it works in AAVE v2. The primary change is in the checks which contains `isInsured` params, if `true`, then full liquidation will be disabled to prevent user from being liquidated due to price drop.

### Check Type of Liquidation

Both liquidation calls, needs to call `checkTypeOfLiquidation` which returns a `unit256`.
If return value:
  - 0: No Liquidation
  - 1: Full Liquidation
  - 2: Micro Liquidaion

This function checks the following conditions of a particular user and based on that returns. The following is the flow diagram for finalizing type of liquidation:
![](./diagrams/checkTypeOfLiquidation.png)

---
