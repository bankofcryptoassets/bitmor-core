import { configuration as actionsConfiguration } from './helpers/actions.js';
import { configuration as calculationsConfiguration } from './helpers/utils/calculations.js';

import fs from 'fs';
import BigNumber from "bignumber.js";

import { makeSuite } from './helpers/make-suite.js';
import { getReservesConfigByPool } from '../../helpers/configuration.js';
import { AavePools, iAavePoolAssets, IReserveParams } from '../../helpers/types.js';
import { executeStory } from './helpers/scenario-engine.js';

const scenarioFolder = './test-suites/test-aave/helpers/scenarios/';

const selectedScenarios: string[] = ['borrow-repay-variable.json'];

fs.readdirSync(scenarioFolder).forEach((file) => {
  if (selectedScenarios.length > 0 && !selectedScenarios.includes(file)) return;

  const scenarioData = fs.readFileSync(`${scenarioFolder}${file}`, 'utf8');
  const scenario = JSON.parse(scenarioData);

  makeSuite(scenario.title, async (testEnv) => {
    before('Initializing configuration', async () => {
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

    for (const story of scenario.stories) {
      it(story.description, async function () {
        // Retry the test scenarios up to 4 times if an error happens, due erratic HEVM network errors 
        this.retries(0);
        await executeStory(story, testEnv);
      });
    }
  });
});
