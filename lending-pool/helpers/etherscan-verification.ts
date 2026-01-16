import { exit } from 'process';
import { DRE } from './misc-utils.js';

const fatalErrors = [
  `The address provided as argument contains a contract, but its bytecode`,
  `Daily limit of 100 source code submissions reached`,
  `has no bytecode. Is the contract deployed to this network`,
  `The constructor for`,
];

const okErrors = [`Contract source code already verified`, 'Already Verified'];

const unableVerifyError = 'Fail - Unable to verify';

export const SUPPORTED_ETHERSCAN_NETWORKS = [
  'main',
  'ropsten',
  'kovan',
  'matic',
  'mumbai',
  'goerli',
  'avalanche',
  'fuji',
  'sepolia',
];

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export const verifyEtherscanContract = async (
  address: string,
  constructorArguments: (string | string[])[],
  libraries?: string
) => {
  const currentNetwork = DRE.network.networkName;

  if (!process.env.ETHERSCAN_KEY) {
    throw Error('Missing process.env.ETHERSCAN_KEY.');
  }
  if (!SUPPORTED_ETHERSCAN_NETWORKS.includes(currentNetwork)) {
    throw Error(
      `Current network ${currentNetwork} not supported. Please change to one of the next networks: ${SUPPORTED_ETHERSCAN_NETWORKS.toString()}`
    );
  }

  try {
    console.log(
      '[ETHERSCAN][WARNING] Delaying Etherscan verification due their API can not find newly deployed contracts'
    );
    const msDelay = 3000;
    const times = 4;

    // Hardhat v3 uses verify task with constructorArgs as array
    const params = {
      address: address,
      constructorArgs: constructorArguments,
    };

    // Add libraries if provided
    if (libraries) {
      (params as any).libraries = libraries;
    }

    await runTaskWithRetry('verify', params, times, msDelay);
  } catch (error) {}
};

export const runTaskWithRetry = async (
  task: string,
  params: any,
  times: number,
  msDelay: number
) => {
  let counter = times;
  await delay(msDelay);

  try {
    if (times > 0) {
      await DRE.tasks.getTask(task).run(params);
    } else {
      console.error(
        '[ETHERSCAN][ERROR] Errors after all the retries, check the logs for more information.'
      );
    }
  } catch (error) {
    counter--;

    if (okErrors.some((okReason) => error.message.includes(okReason))) {
      console.info('[ETHERSCAN][INFO] Skipping due OK response: ', error.message);
      return;
    }

    if (fatalErrors.some((fatalError) => error.message.includes(fatalError))) {
      console.error(
        '[ETHERSCAN][ERROR] Fatal error detected, skip retries and resume deployment.',
        error.message
      );
      return;
    }
    console.error('[ETHERSCAN][ERROR]', error.message);
    console.log();
    console.info(`[ETHERSCAN][[INFO] Retrying attemps: ${counter}.`);
    await runTaskWithRetry(task, params, counter, msDelay);
  }
};

export const checkVerification = () => {
  const currentNetwork = DRE.network.networkName;
  if (!process.env.ETHERSCAN_KEY) {
    console.error('Missing process.env.ETHERSCAN_KEY.');
    exit(3);
  }
  if (!SUPPORTED_ETHERSCAN_NETWORKS.includes(currentNetwork)) {
    console.error(
      `Current network ${currentNetwork} not supported. Please change to one of the next networks: ${SUPPORTED_ETHERSCAN_NETWORKS.toString()}`
    );
    exit(5);
  }
};
