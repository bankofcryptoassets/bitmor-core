import { MAX_UINT_AMOUNT, ZERO_ADDRESS } from '../../helpers/constants.js';
import { buildPermitParams, getSignatureFromTypedData, getContractAddress } from '../../helpers/contracts-helpers.js';
import { expect } from 'chai';

import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { DRE } from '../../helpers/misc-utils.js';
import { waitForTx } from '../../helpers/misc-utils.js';
import { TypedDataEncoder, parseEther } from 'ethers';
import { accounts } from '../../test-wallets.js';
import { depositViaVault } from './helpers/vault-helpers.js';


makeSuite('AToken: Permit', (testEnv: TestEnv) => {
  it('Checks the domain separator', async () => {
    const { aDai } = testEnv;
    const separator = await aDai.DOMAIN_SEPARATOR();

    const domain = {
      name: await aDai.name(),
      version: '1',
      chainId: Number((await DRE.ethers.provider.getNetwork()).chainId),
      verifyingContract: getContractAddress(aDai),
    };
    const domainSeparator = TypedDataEncoder.hashDomain(domain);

    expect(separator).to.be.equal(domainSeparator, 'Invalid domain separator');
  });

  it('Get aDAI for tests', async () => {
    const { dai, deployer } = testEnv;

    // await dai.mint(parseEther('20000'));
    // await dai.approve(getContractAddress(pool), parseEther('20000'));

    // await pool.deposit(getContractAddress(dai), parseEther('20000'), deployer.address, 0);
    await depositViaVault(dai, parseEther('20000'), deployer, testEnv);
  });

  it('Reverts submitting a permit with 0 expiration', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const tokenName = await aDai.name();

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const expiration = 0;
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = parseEther('2').toString();
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      tokenName,
      owner.address,
      spender.address,
      nonce,
      permitAmount,
      expiration.toFixed()
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    expect((await aDai.allowance(owner.address, spender.address)).toString()).to.be.equal(
      '0',
      'INVALID_ALLOWANCE_BEFORE_PERMIT'
    );

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await expect(
      aDai
        .connect(spender.signer)
        .permit(owner.address, spender.address, permitAmount, expiration, v, r, s)
    ).to.be.revertedWith('INVALID_EXPIRATION');

    expect((await aDai.allowance(owner.address, spender.address)).toString()).to.be.equal(
      '0',
      'INVALID_ALLOWANCE_AFTER_PERMIT'
    );
  });

  it('Submits a permit with maximum expiration length', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const deadline = MAX_UINT_AMOUNT;
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = parseEther('2').toString();
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      deadline,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    expect((await aDai.allowance(owner.address, spender.address)).toString()).to.be.equal(
      '0',
      'INVALID_ALLOWANCE_BEFORE_PERMIT'
    );

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await waitForTx(
      await aDai
        .connect(spender.signer)
        .permit(owner.address, spender.address, permitAmount, deadline, v, r, s)
    );

    expect(Number(await aDai._nonces(owner.address))).to.be.equal(1);
  });

  it('Cancels the previous permit', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const deadline = MAX_UINT_AMOUNT;
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = '0';
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      deadline,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    expect((await aDai.allowance(owner.address, spender.address)).toString()).to.be.equal(
      parseEther('2'),
      'INVALID_ALLOWANCE_BEFORE_PERMIT'
    );

    await waitForTx(
      await aDai
        .connect(spender.signer)
        .permit(owner.address, spender.address, permitAmount, deadline, v, r, s)
    );
    expect((await aDai.allowance(owner.address, spender.address)).toString()).to.be.equal(
      permitAmount,
      'INVALID_ALLOWANCE_AFTER_PERMIT'
    );

    expect(Number(await aDai._nonces(owner.address))).to.be.equal(2);
  });

  it('Tries to submit a permit with invalid nonce', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const deadline = MAX_UINT_AMOUNT;
    const nonce = 1000;
    const permitAmount = '0';
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      deadline,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await expect(
      aDai
        .connect(spender.signer)
        .permit(owner.address, spender.address, permitAmount, deadline, v, r, s)
    ).to.be.revertedWith('INVALID_SIGNATURE');
  });

  it('Tries to submit a permit with invalid expiration (previous to the current block)', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const expiration = '1';
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = '0';
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      expiration,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await expect(
      aDai
        .connect(spender.signer)
        .permit(owner.address, spender.address, expiration, permitAmount, v, r, s)
    ).to.be.revertedWith('INVALID_EXPIRATION');
  });

  it('Tries to submit a permit with invalid signature', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const deadline = MAX_UINT_AMOUNT;
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = '0';
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      deadline,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await expect(
      aDai
        .connect(spender.signer)
        .permit(owner.address, ZERO_ADDRESS, permitAmount, deadline, v, r, s)
    ).to.be.revertedWith('INVALID_SIGNATURE');
  });

  it('Tries to submit a permit with invalid owner', async () => {
    const { aDai, deployer, users } = testEnv;
    const owner = deployer;
    const spender = users[1];

    const chainId = Number((await DRE.ethers.provider.getNetwork()).chainId);
    const expiration = MAX_UINT_AMOUNT;
    const nonce = Number(await aDai._nonces(owner.address));
    const permitAmount = '0';
    const msgParams = buildPermitParams(
      chainId,
      getContractAddress(aDai),
      '1',
      await aDai.name(),
      owner.address,
      spender.address,
      nonce,
      expiration,
      permitAmount
    );

    const ownerPrivateKey = accounts[0].secretKey;
    if (!ownerPrivateKey) {
      throw new Error('INVALID_OWNER_PK');
    }

    const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, msgParams);

    await expect(
      aDai
        .connect(spender.signer)
        .permit(ZERO_ADDRESS, spender.address, expiration, permitAmount, v, r, s)
    ).to.be.revertedWith('INVALID_OWNER');
  });
});
