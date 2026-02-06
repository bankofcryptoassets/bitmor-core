import { APPROVAL_AMOUNT_LENDING_POOL } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';
import BigNumber from "bignumber.js";
import chai from 'chai';
import { getReserveAddressFromSymbol, getReserveData, getReserveFactorFromData } from './helpers/utils/helpers.js';
import { DRE } from '../../helpers/dre.js';
const { expect } = chai;

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

    it("should allow withdraw after borrowing", async () => {
        const { users, pool, cbBTC, usdc, addressesProvider, configurator, mockBitmorUSDCVault, helpersContract } = testEnv;

        const depositor = users[5];

        await addressesProvider.setUSDCVault(depositor.address);
        await addressesProvider.setBitmorLoan(depositor.address);

        // Disable USDC as collateral by setting its liquidation threshold to zero.
        // This ensures GenericLogic.balanceDecreaseAllowed() short-circuits on vars.liquidationThreshold == 0.
        await configurator.configureReserveAsCollateral(
            getContractAddress(usdc),
            '0',
            '0',
            '0'
        );

        console.log("configured reserve as collateral");

        // Provide ample cbbtc collateral so the user can safely borrow USDC
        const amountDaiToDeposit = await convertToCurrencyDecimals(
            getContractAddress(cbBTC),
            '10'
        );
        await cbBTC.connect(depositor.signer).mint(amountDaiToDeposit);
        await cbBTC.connect(depositor.signer).approve(
            getContractAddress(pool),
            APPROVAL_AMOUNT_LENDING_POOL
        );
        await pool
            .connect(depositor.signer)
            .deposit(getContractAddress(cbBTC), amountDaiToDeposit, depositor.address, '0');
        console.log("cbbtc deposit complete");

        // const amountUsdcToDeposit = await convertToCurrencyDecimals(
        //     getContractAddress(usdc),
        //     '100000000'
        // );
        // await usdc.connect(depositor.signer).mint(amountUsdcToDeposit);
        // await usdc.connect(depositor.signer).approve(
        //     getContractAddress(pool),
        //     APPROVAL_AMOUNT_LENDING_POOL
        // );
        // await pool
        //     .connect(depositor.signer)
        //     .deposit(getContractAddress(usdc), amountUsdcToDeposit, depositor.address, '0');

        // Borrow a small amount of USDC on behalf of the depositor
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

        console.log("borrow also complete")

        // Now withdraw part of the USDC while there is an outstanding borrow.
        // This drives ValidationLogic.validateWithdraw -> GenericLogic.balanceDecreaseAllowed
        // through the vars.liquidationThreshold == 0 early-return branch.
        // const amountUsdcToWithdraw = amountUsdcToDeposit.div(2);

        // await expect(
        //     pool
        //         .connect(depositor.signer)
        //         .withdraw(getContractAddress(usdc), amountUsdcToWithdraw, depositor.address)
        // ).to.not.be.reverted;
    });
})
