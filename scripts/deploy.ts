import {task} from "hardhat/config";
import {readdir} from "fs/promises";
import {MigrationContext, Network, Stage} from "../deploy/types";
import {ContractWrapperFactory} from "../deploy/ContractWrapperFactory";
import {DeployDataStore} from "../deploy/DataStore";
import path = require("path");
import {FuturesAdapter, FuturesGateway, InsuranceFund} from "../typeChain";
import {BTCBUSD, BNBBUSD, ETHBUSD, CAKEBUSD, DOTBUSD, TRXBUSD, LTCBUSD, AAVEBUSD, ADABUSD, XRPBUSD, MATICBUSD, LINKBUSD, DOGEBUSD, SOLBUSD, UNIBUSD} from "../deploy/config_production";
import { ContractConfig } from "../deploy/shared/PreDefinedContractAddress";
import { loadDb } from "../deploy/shared/utils";

task('deploy', 'deploy contracts', async (taskArgs: { stage: Stage, task: string }, hre, runSuper) => {
    const basePath = path.join(__dirname, "../deploy/migrations")
    const filenames = await readdir(basePath)
    const db = loadDb(taskArgs.stage)
    const context: MigrationContext = {
        stage: taskArgs.stage,
        network: hre.network.name as Network,
        factory: new ContractWrapperFactory(db, hre, new ContractConfig(taskArgs.stage, hre.network.config.chainId, db)),
        db,
        hre
    }

    for (const filename of filenames) {
        console.info(`Start migration: ${filename}`)
        const module = await import(path.join(basePath, filename))
        const tasks = module.default.getTasks(context)
        for (const key of Object.keys(tasks)) {
            if (!taskArgs.task || taskArgs.task == key) {
                console.group(`-- Start run task ${key}`)
                await tasks[key]()
                console.groupEnd()
            }
        }

    }
}).addParam('stage', 'Stage').addOptionalParam('task', 'Task Name')

task('listDeployedContract', 'list all deployed contracts', async (taskArgs: { stage: Stage }) => {
    const db = loadDb(taskArgs.stage)
    const data = await db.listAllContracts()
    for (const obj of data) {
        console.log(obj.key, obj.address)
    }
}).addParam('stage', 'Stage')

task('configManager', 'config manager address and asset in all contract', async (taskArgs: { stage: Stage }, hre) => {
    let busdAddress

    const db = loadDb(taskArgs.stage)
    if (taskArgs.stage == "production") {
        busdAddress = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
    } else if (taskArgs.stage == "okex_main") {
        busdAddress = "0x382bb369d343125bfb2117af9c149795c6c65c50"
    } else if (taskArgs.stage == "test") {
        busdAddress = await db.findAddressByKey("TokenBUSDTestnet")
    } else if (taskArgs.stage == "okex_test") {
        busdAddress = await db.findAddressByKey("TokenBUSDTestnet")
    }



    const insuranceFundAddress = await db.findAddressByKey("InsuranceFund")
    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', insuranceFundAddress) as InsuranceFund

    const futuresGatewayAddress = await db.findAddressByKey("FuturesGateway")
    const futuresGateway = await hre.ethers.getContractAt('FuturesGateway', futuresGatewayAddress) as FuturesGateway

    let res = null;
    try {
        res = [];
        // set manager asset in InsuranceFund
        res.push(await insuranceFund.setManagerAssetMapping('0xe3517d3412e7c7260eb83801fb1b600a81394a3c', busdAddress))
        res.push(await insuranceFund.updateWhitelistManager('0xe3517d3412e7c7260eb83801fb1b600a81394a3c', true))
        // set manager config data in FuturesGateway
        res.push(await futuresGateway.setPositionManagerConfigData(
            '0xe3517d3412e7c7260eb83801fb1b600a81394a3c',
            UNIBUSD.takerTollRatio,
            UNIBUSD.makerTollRatio,
            UNIBUSD.basisPoint,
            UNIBUSD.baseBasisPoint,
            UNIBUSD.contractPrice,
            UNIBUSD.assetRfiPercent,
            UNIBUSD.minimumOrderQuantity,
            UNIBUSD.stepBaseSize
        ))
        console.log("success")
    } catch (err) {
        console.log("fail", err)
    }
}).addParam('stage', 'Stage')

task('addRelayer', 'add whitelist relayer address', async (taskArgs : {stage: Stage}, hre) => {
    const db = loadDb(taskArgs.stage)
    const futuresAdapterAddress = await db.findAddressByKey("FuturesAdapter")
    const futuresAdapter = await hre.ethers.getContractAt('FuturesAdapter', futuresAdapterAddress) as FuturesAdapter

    // TODO add relayer address
    const relayerAddress = '0xA0e782e89209A4e982Ef987dF881C7774D228769'

    await futuresAdapter.updateRelayerStatus(relayerAddress)
}).addParam('stage', 'Stage')

task('addWhitelistAdmin', 'add whitelist admin in insuranceFund', async (taskArgs : {stage: Stage}, hre) => {
    const db = loadDb(taskArgs.stage)
    const insuranceFundAddress = await db.findAddressByKey("InsuranceFund")
    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', insuranceFundAddress) as InsuranceFund

    // TODO add relayer address
    const adminAddress = '0xA0e782e89209A4e982Ef987dF881C7774D228769'

    await insuranceFund.updateAdminStatus(adminAddress, true)
}).addParam('stage', 'Stage')

// task('setBlackList', 'set blacklist trader', async (taskArgs : {stage: Stage}, hre) => {
//     let dataStoreFileName
//     if (taskArgs.stage == "production") {
//         dataStoreFileName = DATA_STORE_FILE['production']
//     } else if (taskArgs.stage == 'test') {
//         dataStoreFileName = DATA_STORE_FILE['test']
//     } else if (taskArgs.stage == 'dev') {
//         dataStoreFileName = DATA_STORE_FILE['dev']
//     }
//
//     const db = new DeployDataStore(dataStoreFileName)
//     const insuranceFundAddress = await db.findAddressByKey("InsuranceFund")
//     const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', insuranceFundAddress) as InsuranceFund
//
//     await insuranceFund.setBlacklistTraders(['0x62a9B1AB58c3B59eF17923792122985d210A94A1'], 2)
// }).addParam('stage', 'Stage')

export default {}
