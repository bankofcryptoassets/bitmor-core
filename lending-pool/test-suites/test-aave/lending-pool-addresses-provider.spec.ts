import chai from 'chai';
const { expect } = chai;
import { createRandomAddress } from '../../helpers/misc-utils.js';
import { makeSuite } from './helpers/make-suite.js';
import type { TestEnv } from './helpers/make-suite.js';
import { ProtocolErrors } from '../../helpers/types.js';
import { keccak256, toUtf8Bytes } from 'ethers';
import { ZERO_ADDRESS } from '../../helpers/constants.js';
import { waitForTx } from '../../helpers/misc-utils.js';
import { deployLendingPool } from '../../helpers/contracts-deployments.js';
import { getContractAddress } from '../../helpers/contracts-helpers.js';

makeSuite('LendingPoolAddressesProvider', (testEnv: TestEnv) => {
  it('Test the accessibility of the LendingPoolAddressesProvider', async () => {
    const { addressesProvider, users } = testEnv;
    const mockAddress = createRandomAddress();
    const { INVALID_OWNER_REVERT_MSG } = ProtocolErrors;

    await addressesProvider.transferOwnership(users[1].address);

    for (const contractFunction of [
      addressesProvider.setMarketId,
      addressesProvider.setLendingPoolImpl,
      addressesProvider.setLendingPoolConfiguratorImpl,
      addressesProvider.setLendingPoolCollateralManager,
      addressesProvider.setPoolAdmin,
      addressesProvider.setPriceOracle,
      addressesProvider.setLendingRateOracle,
    ]) {
      await expect(contractFunction(mockAddress)).to.be.revertedWith(INVALID_OWNER_REVERT_MSG);
    }

    await expect(
      addressesProvider.setAddress(keccak256(toUtf8Bytes('RANDOM_ID')), mockAddress)
    ).to.be.revertedWith(INVALID_OWNER_REVERT_MSG);

    await expect(
      addressesProvider.setAddressAsProxy(
        keccak256(toUtf8Bytes('RANDOM_ID')),
        mockAddress
      )
    ).to.be.revertedWith(INVALID_OWNER_REVERT_MSG);
  });

  it('Tests adding  a proxied address with `setAddressAsProxy()`', async () => {
    const { addressesProvider, users } = testEnv;
    const { INVALID_OWNER_REVERT_MSG } = ProtocolErrors;

    const currentAddressesProviderOwner = users[1];

    const mockLendingPool = await deployLendingPool();
    const proxiedAddressId = keccak256(toUtf8Bytes('RANDOM_PROXIED'));

    const proxiedAddressSetReceipt = await waitForTx(
      await addressesProvider
        .connect(currentAddressesProviderOwner.signer)
        .setAddressAsProxy(proxiedAddressId, getContractAddress(mockLendingPool))
    );

    if (!proxiedAddressSetReceipt.events || proxiedAddressSetReceipt.events?.length < 1) {
      throw new Error('INVALID_EVENT_EMMITED');
    }

    expect(proxiedAddressSetReceipt.events[0].event).to.be.equal('ProxyCreated');
    expect(proxiedAddressSetReceipt.events[1].event).to.be.equal('AddressSet');
    expect(proxiedAddressSetReceipt.events[1].args?.id).to.be.equal(proxiedAddressId);
    expect(proxiedAddressSetReceipt.events[1].args?.newAddress).to.be.equal(
      getContractAddress(mockLendingPool)
    );
    expect(proxiedAddressSetReceipt.events[1].args?.hasProxy).to.be.equal(true);
  });

  it('Tests adding a non proxied address with `setAddress()`', async () => {
    const { addressesProvider, users } = testEnv;
    const { INVALID_OWNER_REVERT_MSG } = ProtocolErrors;

    const currentAddressesProviderOwner = users[1];
    const mockNonProxiedAddress = createRandomAddress();
    const nonProxiedAddressId = keccak256(toUtf8Bytes('RANDOM_NON_PROXIED'));

    const nonProxiedAddressSetReceipt = await waitForTx(
      await addressesProvider
        .connect(currentAddressesProviderOwner.signer)
        .setAddress(nonProxiedAddressId, mockNonProxiedAddress)
    );

    expect(mockNonProxiedAddress.toLowerCase()).to.be.equal(
      (await addressesProvider.getAddress(nonProxiedAddressId)).toLowerCase()
    );

    if (!nonProxiedAddressSetReceipt.events || nonProxiedAddressSetReceipt.events?.length < 1) {
      throw new Error('INVALID_EVENT_EMMITED');
    }

    expect(nonProxiedAddressSetReceipt.events[0].event).to.be.equal('AddressSet');
    expect(nonProxiedAddressSetReceipt.events[0].args?.id).to.be.equal(nonProxiedAddressId);
    expect(nonProxiedAddressSetReceipt.events[0].args?.newAddress).to.be.equal(
      mockNonProxiedAddress
    );
    expect(nonProxiedAddressSetReceipt.events[0].args?.hasProxy).to.be.equal(false);
  });
});
