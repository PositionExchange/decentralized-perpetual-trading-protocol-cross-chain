import {MigrationDefinition} from "../types";
import {verifyContract} from "../../scripts/utils";
const migrations: MigrationDefinition = {
    getTasks: (context) => {
        // only for test stage
        // if(context.stage != 'test') return {}
        async function deployMockBep20(name, symbol){
            // @ts-ignore
            const bep20Mintable = await context.hre.ethers.getContractFactory('PositionBUSDBonus')
            if(await context.db.findAddressByKey(`Mock:${symbol}`) ) return;
            const deployTx = await bep20Mintable.deploy(name, symbol)
            await deployTx.deployTransaction.wait(3)
            await verifyContract(context.hre, deployTx.address, [name, symbol])
            await context.db.saveAddressByKey(`BusdBonus:${symbol}`, deployTx.address)
        }
        return {
            // 'deploy mock BUSD Upgradeable testnet': async () => {
            //     return context.factory.createBUSDTestnet()
            // },
            // 'deploy BUSD bonus': async () => {
            //     return deployMockBep20('BUSD Bonus', 'BUSDP')
            // }
            'deploy mock BUSD Bonus Upgradeable': async () => {
                return context.factory.createBUSDBonus()
            },
        }
    }
}

export default migrations