import { ethers, AbiCoder, parseUnits } from 'ethers';
import type { Contract, Signer, BigNumberish, BaseContract, Addressable } from 'ethers';
import { signTypedData_v4 } from 'eth-sig-util';
import { fromRpcSig, ECDSASignature } from 'ethereumjs-util';
import BigNumber from 'bignumber.js';
import { getDb, DRE, waitForTx, notFalsyOrZeroAddress } from './misc-utils.js';
import {
  eContractid,
  eEthereumNetwork,
  AavePools,
  ePolygonNetwork,
  eXDaiNetwork,
  eAvalancheNetwork,
  eBaseNetwork,
} from './types.js';
import type {
  tEthereumAddress,
  tStringTokenSmallUnits,
  iParamsPerNetwork,
  iParamsPerPool,
  eNetwork,
  iEthereumParamsPerNetwork,
  iPolygonParamsPerNetwork,
  iXDaiParamsPerNetwork,
  iAvalancheParamsPerNetwork,
  iBaseParamsPerNetwork,
} from './types.js';
import type { MintableERC20 } from '../types/ethers-contracts/index.js';
import type { Artifact } from 'hardhat/types/artifacts';
import { verifyEtherscanContract } from './etherscan-verification.js';
import { getIErc20Detailed } from './contracts-getters.js';
import { usingTenderly, verifyAtTenderly } from './tenderly-utils.js';
import { usingPolygon, verifyAtPolygon } from './polygon-utils.js';
import { ConfigNames, loadPoolConfig } from './configuration.js';
import { ZERO_ADDRESS } from './constants.js';
import { getDefenderRelaySigner, usingDefender } from './defender-utils.js';

const utils = { defaultAbiCoder: AbiCoder.defaultAbiCoder(), parseUnits };

export type MockTokenMap = { [symbol: string]: MintableERC20 };

// Helper function to get contract address from ethers v6 BaseContract or legacy contracts
export const getContractAddress = (contract: BaseContract | { address: string }): string => {
  // ethers v6: BaseContract has .target property
  if ('target' in contract) {
    const target = contract.target;
    // In ethers v6, target is the contract address (string)
    if (typeof target === 'string') {
      return target;
    }
  }
  // Legacy contracts (MockContract, etc.) have .address property
  if ('address' in contract && typeof contract.address === 'string') {
    return contract.address;
  }
  // Fallback
  throw new Error('Contract does not have a valid address or target property');
};

export const registerContractInJsonDb = async (contractId: string, contractInstance: any) => {
  const currentNetwork = DRE.network.networkName;
  const FORK = process.env.FORK;
  if (FORK || (currentNetwork !== 'hardhat' && !currentNetwork.includes('coverage'))) {
    console.log(`*** ${contractId} ***\n`);
    console.log(`Network: ${currentNetwork}`);
    console.log(`tx: ${contractInstance.deploymentTransaction?.()?.hash || contractInstance.deployTransaction?.hash || 'N/A'}`);
    console.log(`contract address: ${getContractAddress(contractInstance)}`);
    console.log(`deployer address: ${contractInstance.deploymentTransaction?.()?.from || contractInstance.deployTransaction?.from || 'N/A'}`);
    console.log(`gas price: ${contractInstance.deploymentTransaction?.()?.gasPrice || contractInstance.deployTransaction?.gasPrice || 'N/A'}`);
    console.log(`gas used: ${contractInstance.deploymentTransaction?.()?.gasLimit || contractInstance.deployTransaction?.gasLimit || 'N/A'}`);
    console.log(`\n******`);
    console.log();
  }

  await getDb()
    .set(`${contractId}.${currentNetwork}`, {
      address: getContractAddress(contractInstance),
      deployer: contractInstance.deploymentTransaction?.()?.from || contractInstance.deployTransaction?.from || 'unknown',
    })
    .write();
};

export const insertContractAddressInDb = async (id: eContractid, address: tEthereumAddress) =>
  await getDb()
    .set(`${id}.${DRE.network.networkName}`, {
      address,
    })
    .write();

export const rawInsertContractAddressInDb = async (id: string, address: tEthereumAddress) =>
  await getDb()
    .set(`${id}.${DRE.network.networkName}`, {
      address,
    })
    .write();

export const getEthersSigners = async (): Promise<Signer[]> => {
  const ethersSigners = await Promise.all(await DRE.ethers.getSigners());

  if (usingDefender()) {
    const [, ...users] = ethersSigners;
    return [await getDefenderRelaySigner(), ...users];
  }
  return ethersSigners;
};

export const getEthersSignersAddresses = async (): Promise<tEthereumAddress[]> =>
  await Promise.all((await getEthersSigners()).map((signer) => signer.getAddress()));

export const getFirstSigner = async () => (await getEthersSigners())[0];

export const getCurrentBlock = async () => {
  return DRE.ethers.provider.getBlockNumber();
};

export const decodeAbiNumber = (data: string): number =>
  parseInt(utils.defaultAbiCoder.decode(['uint256'], data).toString());

export const deployContract = async <ContractType extends Contract>(
  contractName: string,
  args: any[]
): Promise<ContractType> => {
  const contract = (await (await DRE.ethers.getContractFactory(contractName))
    .connect(await getFirstSigner())
    .deploy(...args)) as ContractType;
  await contract.waitForDeployment();
  await registerContractInJsonDb(<eContractid>contractName, contract);
  return contract;
};

export const withSaveAndVerify = async <ContractType extends Contract>(
  instance: ContractType,
  id: string,
  args: (string | string[])[],
  verify?: boolean
): Promise<ContractType> => {
  // In ethers v6, use waitForDeployment() instead of waiting for deployTransaction
  await instance.waitForDeployment();
  await registerContractInJsonDb(id, instance);
  if (verify) {
    await verifyContract(id, instance, args);
  }
  return instance;
};

export const getContract = async <ContractType extends Contract>(
  contractName: string,
  address: string
): Promise<ContractType> => (await DRE.ethers.getContractAt(contractName, address)) as ContractType;

export const linkBytecode = (artifact: Artifact, libraries: any) => {
  let bytecode = artifact.bytecode;

  for (const [fileName, fileReferences] of Object.entries(artifact.linkReferences)) {
    for (const [libName, fixups] of Object.entries(fileReferences)) {
      const addr = libraries[libName];

      if (addr === undefined) {
        continue;
      }

      for (const fixup of fixups) {
        bytecode =
          bytecode.substr(0, 2 + fixup.start * 2) +
          addr.substr(2) +
          bytecode.substr(2 + (fixup.start + fixup.length) * 2);
      }
    }
  }

  return bytecode;
};

export const getParamPerNetwork = <T>(param: iParamsPerNetwork<T>, network: eNetwork) => {
  const { main, ropsten, kovan, coverage, buidlerevm, tenderly, goerli } =
    param as iEthereumParamsPerNetwork<T>;
  const { matic, mumbai } = param as iPolygonParamsPerNetwork<T>;
  const { xdai } = param as iXDaiParamsPerNetwork<T>;
  const { avalanche, fuji } = param as iAvalancheParamsPerNetwork<T>;
  const { base, sepolia } = param as iBaseParamsPerNetwork<T>;
  if (process.env.FORK) {
    return param[process.env.FORK as eNetwork] as T;
  }

  switch (network) {
    case eEthereumNetwork.coverage:
      return coverage;
    case eEthereumNetwork.buidlerevm:
      return buidlerevm;
    case eEthereumNetwork.hardhat:
      return buidlerevm;
    case eEthereumNetwork.kovan:
      return kovan;
    case eEthereumNetwork.ropsten:
      return ropsten;
    case eEthereumNetwork.main:
      return main;
    case eEthereumNetwork.tenderly:
      return tenderly;
    case ePolygonNetwork.matic:
      return matic;
    case ePolygonNetwork.mumbai:
      return mumbai;
    case eXDaiNetwork.xdai:
      return xdai;
    case eAvalancheNetwork.avalanche:
      return avalanche;
    case eAvalancheNetwork.fuji:
      return fuji;
    case eEthereumNetwork.goerli:
      return goerli;
    case eBaseNetwork.base:
      return base;
    case eBaseNetwork.sepolia:
      return sepolia;
    default:
      // For unknown networks (like "default" in Hardhat 3), treat as local dev network
      return buidlerevm;
  }
};

export const getOptionalParamAddressPerNetwork = (
  param: iParamsPerNetwork<tEthereumAddress> | undefined | null,
  network: eNetwork
) => {
  if (!param) {
    return ZERO_ADDRESS;
  }
  return getParamPerNetwork(param, network);
};

export const getParamPerPool = <T>(
  { proto, amm, matic, avalanche }: iParamsPerPool<T>,
  pool: AavePools
) => {
  switch (pool) {
    case AavePools.proto:
      return proto;
    case AavePools.amm:
      return amm;
    case AavePools.matic:
      return matic;
    case AavePools.avalanche:
      return avalanche;
    default:
      return proto;
  }
};

export const convertToCurrencyDecimals = async (tokenAddress: tEthereumAddress, amount: string) => {
  const token = await getIErc20Detailed(tokenAddress);
  let decimals = (await token.decimals()).toString();

  return utils.parseUnits(amount, decimals);
};

export const convertToCurrencyUnits = async (tokenAddress: string, amount: string) => {
  const token = await getIErc20Detailed(tokenAddress);
  let decimals = new BigNumber(await token.decimals());
  const currencyUnit = new BigNumber(10).pow(decimals);
  const amountInCurrencyUnits = new BigNumber(amount).div(currencyUnit);
  return amountInCurrencyUnits.toFixed();
};

export const buildPermitParams = (
  chainId: number,
  token: tEthereumAddress,
  revision: string,
  tokenName: string,
  owner: tEthereumAddress,
  spender: tEthereumAddress,
  nonce: number,
  deadline: string,
  value: tStringTokenSmallUnits
) => ({
  types: {
    EIP712Domain: [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
    ],
    Permit: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  primaryType: 'Permit' as const,
  domain: {
    name: tokenName,
    version: revision,
    chainId: chainId,
    verifyingContract: token,
  },
  message: {
    owner,
    spender,
    value,
    nonce,
    deadline,
  },
});

export const getSignatureFromTypedData = (
  privateKey: string,
  typedData: any // TODO: should be TypedData, from eth-sig-utils, but TS doesn't accept it
): ECDSASignature => {
  const signature = signTypedData_v4(Buffer.from(privateKey.substring(2, 66), 'hex'), {
    data: typedData,
  });
  return fromRpcSig(signature);
};

export const buildLiquiditySwapParams = (
  assetToSwapToList: tEthereumAddress[],
  minAmountsToReceive: BigNumberish[],
  swapAllBalances: BigNumberish[],
  permitAmounts: BigNumberish[],
  deadlines: BigNumberish[],
  v: BigNumberish[],
  r: (string | Buffer)[],
  s: (string | Buffer)[],
  useEthPath: boolean[]
) => {
  return utils.defaultAbiCoder.encode(
    [
      'address[]',
      'uint256[]',
      'bool[]',
      'uint256[]',
      'uint256[]',
      'uint8[]',
      'bytes32[]',
      'bytes32[]',
      'bool[]',
    ],
    [
      assetToSwapToList,
      minAmountsToReceive,
      swapAllBalances,
      permitAmounts,
      deadlines,
      v,
      r,
      s,
      useEthPath,
    ]
  );
};

export const buildRepayAdapterParams = (
  collateralAsset: tEthereumAddress,
  collateralAmount: BigNumberish,
  rateMode: BigNumberish,
  permitAmount: BigNumberish,
  deadline: BigNumberish,
  v: BigNumberish,
  r: string | Buffer,
  s: string | Buffer,
  useEthPath: boolean
) => {
  return utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'uint256', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32', 'bool'],
    [collateralAsset, collateralAmount, rateMode, permitAmount, deadline, v, r, s, useEthPath]
  );
};

export const buildFlashLiquidationAdapterParams = (
  collateralAsset: tEthereumAddress,
  debtAsset: tEthereumAddress,
  user: tEthereumAddress,
  debtToCover: BigNumberish,
  useEthPath: boolean
) => {
  return utils.defaultAbiCoder.encode(
    ['address', 'address', 'address', 'uint256', 'bool'],
    [collateralAsset, debtAsset, user, debtToCover, useEthPath]
  );
};

export const buildParaSwapLiquiditySwapParams = (
  assetToSwapTo: tEthereumAddress,
  minAmountToReceive: BigNumberish,
  swapAllBalanceOffset: BigNumberish,
  swapCalldata: string | Buffer,
  augustus: tEthereumAddress,
  permitAmount: BigNumberish,
  deadline: BigNumberish,
  v: BigNumberish,
  r: string | Buffer,
  s: string | Buffer
) => {
  return utils.defaultAbiCoder.encode(
    [
      'address',
      'uint256',
      'uint256',
      'bytes',
      'address',
      'tuple(uint256,uint256,uint8,bytes32,bytes32)',
    ],
    [
      assetToSwapTo,
      minAmountToReceive,
      swapAllBalanceOffset,
      swapCalldata,
      augustus,
      [permitAmount, deadline, v, r, s],
    ]
  );
};

export const verifyContract = async (
  id: string,
  instance: Contract,
  args: (string | string[])[]
) => {
  if (usingTenderly()) {
    await verifyAtTenderly(id, instance);
  }
  await verifyEtherscanContract(instance.address, args);
  return instance;
};

export const getContractAddressWithJsonFallback = async (
  id: string,
  pool: ConfigNames
): Promise<tEthereumAddress> => {
  const poolConfig = loadPoolConfig(pool);
  const network = <eNetwork>DRE.network.networkName;
  const db = getDb();

  const contractAtMarketConfig = getOptionalParamAddressPerNetwork(poolConfig[id], network);
  if (notFalsyOrZeroAddress(contractAtMarketConfig)) {
    return contractAtMarketConfig;
  }

  const contractAtDb = await getDb().get(`${id}.${DRE.network.networkName}`).value();
  if (contractAtDb?.address) {
    return contractAtDb.address as tEthereumAddress;
  }
  throw Error(`Missing contract address ${id} at Market config and JSON local db`);
};
