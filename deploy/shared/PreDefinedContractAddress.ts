import { DeployDataStore } from "../DataStore";
import { Stage } from "../types";
import { addresses, AvailableStageConfig, stageConfig } from "./config";

// Helper to get predefined contract address
// The mainnet contract should be predefined in config file
export class ContractConfig {
  constructor(protected stage: Stage, protected networkId: number, protected db: DeployDataStore) {
  }

  async getContractAddress(contractName: string): Promise<string> {
    // 1. get from config.ts
    // 2. get from db
    // 3. create mock Contract
    const configAddress = this._getAddressFromConfig(contractName)
    if (configAddress) return configAddress
    const dbAddress = await this.db.findAddressByKey(`Mock:${contractName}`)
    if (dbAddress) return dbAddress
    if(this.stage === "production"){
        throw new Error(`Contract ${contractName} not found`)
    }
    return this._createMockAddress(contractName)
  }

  getStageConfig<T extends any>(name: AvailableStageConfig){
    const config = ((stageConfig[this.stage] || {})[this.networkId] || {})[name]
    if(!config){
        throw new Error(`Config ${name} not found, for network ${this.networkId}`)
    }
    return config
  }

  private _createMockAddress(contractName: string): string | PromiseLike<string> {
      throw new Error("_createMockAddress not implemented.");
  }

  private _getAddressFromConfig(contractName: string): string | null {
    return ((addresses[this.stage] || {})[this.networkId] || {})[contractName] || null
  }
}
