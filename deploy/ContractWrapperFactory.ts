import {
    CreateChainLinkPriceFeed,
    CreateFuturesAdapter,
    CreateFuturesGateway,
} from "./types";
import {DeployDataStore} from "./DataStore";
import {verifyContract} from "../scripts/utils";
import {TransactionResponse} from "@ethersproject/abstract-provider";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {HardhatDefenderUpgrades} from "@openzeppelin/hardhat-defender";
import {FuturesAdapter, InsuranceFund, PositionBUSDBonus} from "../typeChain";


export class ContractWrapperFactory {
    defender: HardhatDefenderUpgrades

    constructor(readonly db: DeployDataStore, readonly hre: HardhatRuntimeEnvironment) {
        this.defender = hre.defender
    }

    async verifyContractUsingDefender(proposal : any){
        console.log("Upgrade proposal created at:", proposal.url);
        const receipt = await proposal.txResponse.wait()
        console.log(`Contract address ${receipt.contractAddress}`)
        await verifyContract(this.hre, receipt.contractAddress)
    }

    async verifyImplContract(deployTransaction: TransactionResponse) {
        const {data} = deployTransaction
        const decodedData = this.hre.ethers.utils.defaultAbiCoder.decode(
            ['address', 'address'],
            this.hre.ethers.utils.hexDataSlice(data, 4)
        );
        const implContractAddress = decodedData[1]
        const isVerified = await this.db.findAddressByKey(`${implContractAddress}:verified`)
        if (isVerified) return console.log(`Implement contract already verified`)
        console.log("Upgraded to impl contract", implContractAddress)
        try {
            await verifyContract(this.hre, implContractAddress)
            await this.db.saveAddressByKey(`${implContractAddress}:verified`, 'yes')
        } catch (err) {
            if (err.message == 'Contract source code already verified') {
                await this.db.saveAddressByKey(`${implContractAddress}:verified`, 'yes')
            }
            console.error(`-- verify contract error`, err)
        }
    }

    async verifyProxy(proxyAddress: string){
        // // Ref: https://docs.openzeppelin.com/upgrades-plugins/1.x/api-hardhat-upgrades#verify
        // return this.hre.run('verify', {address: proxyAddress}).catch(e => {
        //     console.error(`Verify ${proxyAddress} Error`, e)
        // })
    }

    async createInsuranceFund(args) {
        const InsuranceFund = await this.hre.ethers.getContractFactory("InsuranceFund");
        const insuranceFundContractAddress = await this.db.findAddressByKey(`InsuranceFund`);
        if (insuranceFundContractAddress) {
            console.log(`Preparing proposal...`)
            const proposal = await this.hre.defender.proposeUpgrade(insuranceFundContractAddress, InsuranceFund);
            await this.verifyContractUsingDefender(proposal)
            // const upgraded = await this.hre.upgrades.forceImport(insuranceFundContractAddress, InsuranceFund);
            // await this.verifyImplContract(upgraded.deployTransaction);

            const busdBonusAddress = await this.db.findAddressByKey(`BusdBonus:BUSDP`)
            const busdBonus = await this.hre.ethers.getContractAt('PositionBUSDBonus', busdBonusAddress) as PositionBUSDBonus
            const insuranceFund = await this.hre.ethers.getContractAt('InsuranceFund', insuranceFundContractAddress) as InsuranceFund
            let res = null;
            try {
                res = [];
                // res.push(await busdBonus.updateTransferableAddress(insuranceFundContractAddress, true))
                // res.push(await insuranceFund.setBUSDBonusAddress(busdBonusAddress))
                // res.push(await insuranceFund.shouldAcceptBonus(true))
                console.log("success")
            } catch (err) {
                console.log("fail", err)
            }
        } else {
            const contractArgs = [];
            const instance = await this.hre.upgrades.deployProxy(InsuranceFund, contractArgs);
            console.log("wait for deploy insurance fund");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`InsuranceFund address : ${address}`)
            await this.db.saveAddressByKey('InsuranceFund', address);
            await this.verifyProxy(address)
        }
    }

    async createFuturesGateway(args: CreateFuturesGateway,) {
        const FuturesGateway = await this.hre.ethers.getContractFactory("FuturesGateway");
        const FuturesGatewayContractAddress = await this.db.findAddressByKey(`FuturesGateway`);
        if (FuturesGatewayContractAddress) {
            const proposal = await this.hre.defender.proposeUpgrade(FuturesGatewayContractAddress, FuturesGateway);
            await this.verifyContractUsingDefender(proposal)
            // console.log(`Proposal created`, proposal.url)
            // const upgraded = await this.hre.upgrades.upgradeProxy(FuturesGatewayContractAddress, FuturesGateway, {unsafeAllowLinkedLibraries: true});
            // console.log(`Starting verify upgrade futures gateway`)
            // await this.verifyImplContract(upgraded.deployTransaction)
            console.log(`Upgrade FuturesGateway`)
            console.log(FuturesGatewayContractAddress)
            const insuranceFund = await this.hre.ethers.getContractAt('InsuranceFund', args.insuranceFund) as InsuranceFund

            const futureAdapter = await this.hre.ethers.getContractAt('FuturesAdapter', args.futuresAdapter) as FuturesAdapter
            let res;
            try {
                res = [];
                // set manager asset in InsuranceFund
                // res.push(await insuranceFund.setCounterParty(FuturesGatewayContractAddress))
                // res.push(await futureAdapter.updateFuturesGateway(FuturesGatewayContractAddress))
                // set manager config data in FuturesGateway

                console.log("success")
            } catch (err) {
                console.log("fail", err)
            }
        } else {
            const contractArgs = [
                args.futuresAdapter,
                args.posiCrosschainGatewayAddress,
                args.posiChainId,
                args.insuranceFund
            ];
            console.log("before deploy proxy")
            console.log(contractArgs)
            const instance = await this.hre.upgrades.deployProxy(FuturesGateway, contractArgs);
            console.log("wait for deploy futures gateway contract");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`FuturesGateway contract address : ${address}`)
            await this.db.saveAddressByKey('FuturesGateway', address);
            await this.verifyProxy(address)

        }
    }

    async createFuturesAdapter(args: CreateFuturesAdapter) {
        const FuturesAdapter = await this.hre.ethers.getContractFactory("FuturesAdapter");
        const futuresAdapterContractAddress = await this.db.findAddressByKey(`FuturesAdapter`);
        if (futuresAdapterContractAddress) {
            const proposal = await this.hre.defender.proposeUpgrade(futuresAdapterContractAddress, FuturesAdapter);
            await this.verifyContractUsingDefender(proposal)
            // const upgraded = await this.hre.upgrades.upgradeProxy(futuresAdapterContractAddress, FuturesAdapter, {unsafeAllowLinkedLibraries: true});
            // console.log(`Starting verify upgrade futures gateway`)
            // await this.verifyImplContract(upgraded.deployTransaction)
            // console.log(`Proposal created`, proposal.url)
        } else {
            const contractArgs = [
                args.myBlockchainId,
                args.timeHorizon,
            ];
            console.log("before deploy proxy", contractArgs)
            const instance = await this.hre.upgrades.deployProxy(FuturesAdapter, contractArgs);
            console.log("wait for deploy futures adapter contract");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`FuturesAdapter contract address : ${address}`)
            await this.db.saveAddressByKey('FuturesAdapter', address);
            await this.verifyProxy(address)
        }
    }

    async createChainlinkPriceFeed( args: CreateChainLinkPriceFeed){
        const ChainLinkPriceFeed = await this.hre.ethers.getContractFactory("ChainLinkPriceFeed");
        const chainlinkContractAddress = await this.db.findAddressByKey(`ChainLinkPriceFeed`);
        console.log(chainlinkContractAddress)
        if (chainlinkContractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(chainlinkContractAddress, ChainLinkPriceFeed);
            console.log(`Starting verify upgrade ChainLinkPriceFeed`)
            await this.verifyImplContract(upgraded.deployTransaction)
            console.log(`Upgrade ChainLinkPriceFeed`)
        } else {
            const contractArgs = [];
            const instance = await this.hre.upgrades.deployProxy(ChainLinkPriceFeed, contractArgs);
            console.log("wait for deploy chainlink price feed");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`Chain link price feed address : ${address}`)
            await this.db.saveAddressByKey('ChainLinkPriceFeed', address);
            await this.verifyProxy(address)
        }
    }

    async createBUSDTestnet(){
        const tokenBusdTestnetFactory = await this.hre.ethers.getContractFactory('TokenBUSDTestnet')
        const tokenAddress = await this.db.findAddressByKey(`TokenBUSDTestnet`);
        console.log(tokenAddress)
        if (tokenAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(tokenAddress, tokenBusdTestnetFactory);
            console.log(`Starting verify upgrade Token busd testnet`)
            await this.verifyImplContract(upgraded.deployTransaction)
            console.log(`Upgrade BUSD testnet`)
        } else {
            const contractArgs = [];
            const instance = await this.hre.upgrades.deployProxy(tokenBusdTestnetFactory, contractArgs);
            console.log("wait for deploy TokenBUSDTestnet");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`Address TokenBUSDTestnet : ${address}`)
            await this.db.saveAddressByKey('TokenBUSDTestnet', address);
            await this.verifyProxy(address)
        }
        // const instance = await this.hre.upgrades.deployProxy(Contract, []);
        // await instance.deployed();
        // const address = instance.address.toString().toLowerCase();
        // console.log(`Address TokenBUSDTestnet : ${address}`)
        // await this.db.saveAddressByKey('TokenBUSDTestnet', address);
        // await this.verifyProxy(address)
    }

    async createBUSDBonus(){
        const tokenBusdTestnetFactory = await this.hre.ethers.getContractFactory('PositionBUSDBonus')
        const tokenAddress = await this.db.findAddressByKey(`BusdBonus:BUSDP`);
        console.log(tokenAddress)
        if (tokenAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(tokenAddress, tokenBusdTestnetFactory);
            console.log(`Starting verify upgrade Token PositionBUSDBonus`)
            await this.verifyImplContract(upgraded.deployTransaction)
            console.log(`Upgrade PositionBUSDBonus`)
        } else {
            const contractArgs = [];
            const instance = await this.hre.upgrades.deployProxy(tokenBusdTestnetFactory, contractArgs);
            console.log("wait for deploy PositionBUSDBonus");
            await instance.deployed();
            const address = instance.address.toString().toLowerCase();
            console.log(`Address PositionBUSDBonus : ${address}`)
            await this.db.saveAddressByKey('BusdBonus:BUSDP', address);
            await this.verifyProxy(address)
        }
    }
}
