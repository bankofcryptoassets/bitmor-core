import { APPROVAL_AMOUNT_LENDING_POOL } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';
import BigNumber from "bignumber.js";
import { expect } from 'chai';
import { getReserveAddressFromSymbol, getReserveData, getReserveFactorFromData } from './helpers/utils/helpers.js';
import { DRE } from '../../helpers/dre.js';

makeSuite('Withdraw', (testEnv) => {
    it("should allow withdraw after setting reserve factor to zero", async () => {
        const { users, pool, usdc, addressesProvider, helpersContract, configurator } = testEnv;

        const depositor = users[5];

        await addressesProvider.setUSDCVault(depositor.address);

        const amountUsdcToDeposit = await convertToCurrencyDecimals(
            getContractAddress(usdc),
            '100000000'
        );
        await usdc.connect(depositor.signer).mint(amountUsdcToDeposit);
        await usdc.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(usdc), amountUsdcToDeposit, depositor.address, '0');
        await configurator.setReserveFactor(getContractAddress(usdc), "0");

        const config = await pool.getConfiguration(getContractAddress(usdc));
        const reserveFactor = getReserveFactorFromData(new BigNumber(config.data));
        console.log("reserveFactor:: ", reserveFactor);

        expect(reserveFactor.toString()).to.be.equals("0");

        await expect(
            pool.connect(depositor.signer).withdraw(
                getContractAddress(usdc),
                amountUsdcToDeposit,
                depositor.address
            )
        ).to.not.be.rejected;
    });

    it("should allow withdraw after borrowing and repaying all debt", async () => {
        // This test covers GenericLogic.balanceDecreaseAllowed lines 88-90:
        // if (vars.totalDebtInETH == 0) { return true; }
        const { users, pool, btcVault, usdc, addressesProvider, mockBitmorUSDCVault, helpersContract } = testEnv;

        const depositor = users[5];

        await addressesProvider.setUSDCVault(depositor.address);
        await addressesProvider.setBitmorLoan(depositor.address);

        // Deposit bvBTC (vault shares) as collateral (has liquidationThreshold > 0)
        const amountBvBTCToDeposit = await convertToCurrencyDecimals(
            getContractAddress(btcVault),
            '10'
        );
        await btcVault.mint(depositor.address, amountBvBTCToDeposit);
        await btcVault.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(btcVault), amountBvBTCToDeposit, depositor.address, '0');

        // Deposit USDC to provide liquidity for borrowing
        const amountUsdcToDeposit = await convertToCurrencyDecimals(
            getContractAddress(usdc),
            '100000'
        );
        await usdc.connect(depositor.signer).mint(amountUsdcToDeposit);
        await usdc.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(usdc), amountUsdcToDeposit, depositor.address, '0');

        // Borrow USDC
        const amountUsdcToBorrow = await convertToCurrencyDecimals(
            getContractAddress(usdc),
            '1000'
        );

        await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);

        const {variableDebtTokenAddress} = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
        const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
        await Vdt.connect(depositor.signer).approveDelegation(
            pool.target,
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        );

        await pool.connect(depositor.signer).borrow(
            getContractAddress(usdc),
            amountUsdcToBorrow,
            2, // variable rate
            0, // referralCode
            depositor.address
        );

        // Repay all debt - use max uint256 to repay entire balance
        await usdc.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool.connect(depositor.signer).repay(
            getContractAddress(usdc),
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", // max uint256 = repay all
            2, // variable rate
            depositor.address
        );

        // Now withdraw bvBTC - user has collateral with liquidationThreshold > 0 but NO debt
        // This hits GenericLogic.balanceDecreaseAllowed lines 88-90: if (vars.totalDebtInETH == 0) return true
        const amountBvBTCToWithdraw = amountBvBTCToDeposit / 2n;

        await expect(
            pool
                .connect(depositor.signer)
                .withdraw(getContractAddress(btcVault), amountBvBTCToWithdraw, depositor.address)
        ).to.not.be.rejected;
    });

    it("should allow partial withdraw with outstanding debt (covers health factor calculation)", async () => {
        // This test covers GenericLogic.balanceDecreaseAllowed lines 102-115:
        // The health factor calculation path when user has collateral AND debt
        const { users, pool, btcVault, usdc, addressesProvider, mockBitmorUSDCVault, helpersContract } = testEnv;

        const depositor = users[6];

        await addressesProvider.setUSDCVault(depositor.address);
        await addressesProvider.setBitmorLoan(depositor.address);

        // Deposit bvBTC (vault shares) as collateral (has liquidationThreshold > 0)
        const amountBvBTCToDeposit = await convertToCurrencyDecimals(
            getContractAddress(btcVault),
            '10'
        );
        await btcVault.mint(depositor.address, amountBvBTCToDeposit);
        await btcVault.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(btcVault), amountBvBTCToDeposit, depositor.address, '0');

        // Deposit USDC to provide liquidity for borrowing
        const amountUsdcToDeposit = await convertToCurrencyDecimals(
            getContractAddress(usdc),
            '100000'
        );
        await usdc.connect(depositor.signer).mint(amountUsdcToDeposit);
        await usdc.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(usdc), amountUsdcToDeposit, depositor.address, '0');

        // Borrow USDC (creates debt)
        const amountUsdcToBorrow = await convertToCurrencyDecimals(
            getContractAddress(usdc),
            '1000'
        );

        await addressesProvider.setUSDCVault(mockBitmorUSDCVault.target);

        const {variableDebtTokenAddress} = await helpersContract.getReserveTokensAddresses(getContractAddress(usdc));
        const Vdt = await DRE.ethers.getContractAt("VariableDebtToken", variableDebtTokenAddress);
        await Vdt.connect(depositor.signer).approveDelegation(
            pool.target,
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        );

        await pool.connect(depositor.signer).borrow(
            getContractAddress(usdc),
            amountUsdcToBorrow,
            2, // variable rate
            0, // referralCode
            depositor.address
        );

        // Withdraw a small amount of bvBTC while having outstanding debt
        // This triggers the health factor calculation at lines 102-115:
        // - liquidationThreshold > 0 (passes lines 76-78)
        // - totalDebtInETH > 0 (passes lines 88-90)
        // - collateralBalanceAfterDecrease > 0 (passes lines 99-101)
        // - Executes health factor calculation at lines 103-115
        const amountBvBTCToWithdraw = amountBvBTCToDeposit / 10n; // Small amount to keep health factor safe

        await expect(
            pool
                .connect(depositor.signer)
                .withdraw(getContractAddress(btcVault), amountBvBTCToWithdraw, depositor.address)
        ).to.not.be.rejected;
    });
})
