// Use any type for DRE in Hardhat 3 to avoid import issues
export let DRE: any;

export const setDRE = (_DRE: any) => {
  DRE = _DRE;
};
