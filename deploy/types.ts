import { ContractWrapperFactory } from "./ContractWrapperFactory";
import { DeployDataStore } from "./DataStore";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export type MigrationTask = () => Promise<void>;

export interface MigrationDefinition {
    configPath?: string
    getTasks: (context: MigrationContext) => {
        [taskName: string]: MigrationTask
    }
}

export type Stage = "production" | "staging" | "test" | "dev" | "okex_test" | "okex_main" | "arbitrumGoerli" | "arbitrumOne"
export type Network = "bsc_testnet" | "bsc_mainnet" | "qc"

export interface MigrationContext {
    stage: Stage
    network: Network
    factory: ContractWrapperFactory
    db: DeployDataStore
    hre: HardhatRuntimeEnvironment
}

export interface CreateFuturesGateway {
    futuresAdapter: string,
    posiCrosschainGatewayAddress: string,
    posiChainId: number,
    insuranceFund: string
}

export interface CreateFuturesAdapter {
    myBlockchainId: number,
    timeHorizon: number
}

export interface CreateChainLinkPriceFeed {

}

export interface PositionManagerConfigData {
    positionManagerAddress: string,
    takerTollRatio: number,
    makerTollRatio: number,
    basisPoint: number,
    baseBasisPoint: number,
    contractPrice: number,
    assetRfiPercent: number,
    minimumOrderQuantity: string,
    stepBaseSize: number
}

export interface CreateDptpFuturesGateway {
    pcsId: number,
    pscCrossChainGateway: string,
    futuresAdapter: string,
    vault: string,
    weth: string,
    gatewayUtils: string,
    futurXGatewayStorage: string,
    executionFee: number,
}

export interface CreateReferralRewardTracker {
    rewardToken: string,
    tokenDecimal: number,
}
