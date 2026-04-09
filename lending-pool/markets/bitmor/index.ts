import { eBaseNetwork, eEthereumNetwork, IBitmorConfiguration } from "../../helpers/types.js";
import { BitmorCommonsConfig } from "./commons.js";
import { strategyUSDC, strategyBVBTC } from "./reservesConfigs.js";
export const BitmorConfig: IBitmorConfiguration = {
    ...BitmorCommonsConfig,
    MarketId: "Bitmor Lending Market",
    ProviderId: 100,
    ReservesConfig: {
        USDC: strategyUSDC,
        bvBTC: strategyBVBTC,
    },
    ReserveAssets: {
        [eBaseNetwork.base]: {
            USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            bvBTC: "", // To be populated from loan-provider deployment
        },
        [eBaseNetwork.sepolia]: {
            USDC: "", // To be populated from loan-provider deployment (debtAsset)
            bvBTC: "", // To be populated from loan-provider deployment (collateralAsset)
        },
        // For hardhat/localhost, addresses are loaded dynamically from deployed-contracts.json
        // This will be populated at runtime by getParamPerNetwork
        [eEthereumNetwork.hardhat]: {},
    },
};

export default BitmorConfig;
