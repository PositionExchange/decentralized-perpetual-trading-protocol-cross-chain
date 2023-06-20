import dotenv from "dotenv";

dotenv.config();

export const BUSD = "BUSD";
export const POSI = "POSI";

export const ARB_API_KEY = process.env["ARB_API_KEY"];
export const ARB_TESTNET_DEPLOYER_KEY = process.env["ARB_TESTNET_DEPLOYER_KEY"];
export const ARB_MAINNET_DEPLOYER_KEY = process.env["ARB_MAINNET_DEPLOYER_KEY"];

export const BSC_API_KEY = process.env["BSC_API_KEY"];
export const BSC_TESTNET_DEPLOYER_KEY = process.env["BSC_TESTNET_DEPLOYER_KEY"];
export const BSC_MAINNET_DEPLOYER_KEY = process.env["BSC_TESTNET_DEPLOYER_KEY"];
