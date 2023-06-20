import { DeployDataStore } from "../DataStore";
import { Stage } from "../types";
import { hexToBytes } from "web3-utils";
import { ethers } from "ethers";

const DATA_STORE_FILE = {
  "usd-m": "./deployData_mainnet.db",
  "coin-m": "./deployData_mainnet_coin_m.db",
  dev: "./deployData_geth.db",
  test: "./deployData_bsc_testnet.db",
  production: "./deployData_mainnet.db",
  okex_test: "./deployData_okex_testnet.db",
  okex_main: "./deployData_okex_mainnet.db",
  arbitrumGoerli: "./deployData_arb_goerli.db",
  arbitrumOne: "./deployData_arb_one.db",
};

export function loadDb(stage: Stage) {
  return new DeployDataStore(DATA_STORE_FILE[stage]);
}

export function encodeDelegateCall(_abi: string[], _fName: string, _values: any[]): number[] {
  const iFace = new ethers.utils.Interface(_abi);
  const encodedData = iFace.encodeFunctionData(_fName, _values);
  console.log(encodedData)
  return hexToBytes(encodedData);
}
