export interface DeployedContract {
  name: string;
  address: string;
  type: "CREATE" | "CREATE2";
  deployer: string;
}

export interface DeployedLibrary {
  path: string;
  name: string;
  address: string;
}

export interface BroadcastResult {
  chainId: number;
  commit: string;
  timestamp: number;
  deployer: string;
  contracts: DeployedContract[];
  libraries: DeployedLibrary[];
}

export function parseBroadcast(json: any): BroadcastResult {
  const contracts: DeployedContract[] = [];

  for (const tx of json.transactions ?? []) {
    if (tx.transactionType === "CREATE" || tx.transactionType === "CREATE2") {
      contracts.push({
        name: tx.contractName,
        address: tx.contractAddress,
        type: tx.transactionType,
        deployer: tx.transaction?.from ?? "",
      });
    }
  }

  const libraries: DeployedLibrary[] = (json.libraries ?? []).map((lib: string) => {
    // Format: "src/path/Lib.sol:LibName:0xAddress"
    const parts = lib.split(":");
    return {
      path: parts[0],
      name: parts[1],
      address: parts[2],
    };
  });

  return {
    chainId: json.chain,
    commit: json.commit ?? "",
    timestamp: json.timestamp ?? Date.now(),
    deployer: contracts[0]?.deployer ?? "",
    contracts,
    libraries,
  };
}
