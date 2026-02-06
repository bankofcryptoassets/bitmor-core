import { configuration as actionsConfiguration } from '../helpers/actions.js';
import { configuration as calculationsConfiguration } from '../helpers/utils/calculations.js';

import fs from 'fs';
import BigNumber from "bignumber.js";

import { makeSuite } from '../helpers/make-suite.js';
import { getReservesConfigByPool } from '../../../helpers/configuration.js';
import { AavePools, iAavePoolAssets, IReserveParams } from '../../../helpers/types.js';
import { executeStory } from '../helpers/scenario-engine.js';

const scenarioData = fs.readFileSync('./test-suites/test-aave/helpers/scenarios/borrow-repay-stable.json', 'utf8');
const loadedScenario = JSON.parse(scenarioData);

makeSuite('Subgraph scenario tests', async (testEnv) => {
  let story: any;
  let scenario;
  before('Initializing configuration', async () => {
    scenario = loadedScenario;
    story = scenario.stories[0];
    // Sets BigNumber for this suite, instead of globally
    BigNumber.config({ DECIMAL_PLACES: 0, ROUNDING_MODE: BigNumber.ROUND_DOWN });

    actionsConfiguration.skipIntegrityCheck = false; //set this to true to execute solidity-coverage

    calculationsConfiguration.reservesParams = <iAavePoolAssets<IReserveParams>>(
      getReservesConfigByPool(AavePools.proto)
    );
  });
  after('Reset', () => {
    // Reset BigNumber
    BigNumber.config({ DECIMAL_PLACES: 20, ROUNDING_MODE: BigNumber.ROUND_HALF_UP });
  });
  it('deposit-borrow', async () => {
    await executeStory(story, testEnv);
  });
});
