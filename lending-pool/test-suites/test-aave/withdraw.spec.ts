import { APPROVAL_AMOUNT_LENDING_POOL } from '../../helpers/constants.js';
import { convertToCurrencyDecimals, getContractAddress } from '../../helpers/contracts-helpers.js';
import { makeSuite } from './helpers/make-suite.js';

import chai from 'chai';
const { expect } = chai;

makeSuite('Withdraw', (testEnv) => {
    it("shoudld allow withdrawal after setting liquidation threshold to zero", async () => {
        const { users, pool, usdc, addressesProvider } = testEnv;

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
        
        const userAccountData = await pool.getUserAccountData(depositor.address);
        console.log("deposito.address:: ", depositor.address);
        console.log("userAccountData:: ", userAccountData, userAccountData.totalDebtETH.toString());

        const userConfig = await pool.getUserConfiguration(depositor.address);
        console.log("userConfig:: ", userConfig, userConfig);

        expect(userAccountData.totalDebtETH.toString()).to.be.equal("0");

        await pool.connect(depositor.signer).withdraw(
            getContractAddress(usdc),
            amountUsdcToDeposit,
            depositor.address
        );
    })
})
