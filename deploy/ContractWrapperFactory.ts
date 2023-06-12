import {
    CreateChainLinkPriceFeed,
    CreateDptpFuturesGateway,
    CreateFuturesAdapter,
    CreateFuturesGateway,
    CreateReferralRewardTracker,
} from "./types";
import {DeployDataStore} from "./DataStore";
import {verifyContract} from "../scripts/utils";
import {TransactionResponse} from "@ethersproject/abstract-provider";
import {HardhatRuntimeEnvironment} from "hardhat/types";
// @ts-ignore
import {HardhatDefenderUpgrades} from "@openzeppelin/hardhat-defender";
import {
    DptpFuturesGateway,
    FuturesAdapter,
    FuturXVoucher,
    InsuranceFund,
    LpManager,
    MockToken,
    PLP,
    PositionBUSDBonus,
    PriceFeed,
    ReferralRewardTracker,
    USDP,
    Vault,
    VaultPriceFeed,
    VaultUtils,
    WETH,
} from "../typeChain";
import {ContractConfig} from "./shared/PreDefinedContractAddress";
import {ethers as ethersE} from "ethers";
import {IExtraTokenConfig, Token} from "./shared/types";

interface ContractWrapperFactoryOptions {
    isForceDeploy?: boolean;
}

export class ContractWrapperFactory {
    defender: HardhatDefenderUpgrades
    isForceDeploy: boolean

    constructor(readonly db: DeployDataStore, readonly hre: HardhatRuntimeEnvironment, public readonly contractConfig: ContractConfig, options: ContractWrapperFactoryOptions = {}) {
        this.defender = hre.defender
        this.isForceDeploy = options.isForceDeploy || false
    }

    async verifyContractUsingDefender(proposal: any) {
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

    async getDeployedContract<T>(contractId: string, contractName?: string): Promise<T> {
        if (!contractName) {
            contractName = contractId
        }
        const address = await this.db.findAddressByKey(contractId)
        console.log(`ID: ${contractId} Address: ${address}`)
        if (!address) throw new Error(`Contract ${contractId} not found`)
        const contract = await this.hre.ethers.getContractAt(contractName, address)
        return contract as T
    }

    async deployNonUpgradeableContract<T extends ethersE.Contract>(contractName: string, args: any[] = [], options: {
        contractId?: string
    } = {}): Promise<T> {
        const contractId = options.contractId || contractName
        if (!this.isForceDeploy) {
            // check for contract exists
            // if exists, return the address
            const savedAddress = await this.db.findAddressByKey(contractId)
            if (savedAddress) {
                console.log(`Contract ${contractId} already deployed at ${savedAddress}`)
                console.log('Tips: use --force to force deploy')
                const contractIns = await this.hre.ethers.getContractAt(contractName, savedAddress)
                return contractIns as T
            }
        }
        console.log(`Start deploying contract ${contractId}... with args:`, args)
        const contract = await this.hre.ethers.getContractFactory(contractName);
        const contractIns = await contract.deploy(...args);
        await contractIns.deployTransaction.wait(3);
        try {
            await verifyContract(this.hre, contractIns.address, args)
        } catch (err) {
            console.error(`-- verify contract error, skipping...`, err)
        }
        console.log(`Contract ${contractName} deployed at:`, contractIns.address)
        await this.db.saveAddressByKey(contractId, contractIns.address)
        return contractIns as T
    }

    async waitTx(tx: Promise<ethersE.ContractTransaction>, name = '', skipOnFail = false): Promise<ethersE.ContractReceipt> {
        // name match initialize, auto skipping
        if (name.match(/initialize/i) && !skipOnFail) {
            skipOnFail = true;
        }
        try {
            console.log(`Waiting for tx ${name}...`)
            const txResponse = await tx
            console.log(`Tx ${name} hash ${txResponse.hash}`)
            const receipt = await txResponse.wait()
            console.log(`Tx [${name}] tx ${txResponse.hash} mined at block ${receipt.blockNumber}`)
            return receipt

        } catch (err) {
            console.log(`Tx ${name} failed with the following error:`)
            if (skipOnFail) {
                console.error(`-- tx ${name} failed, skipping...`, err)
                return null
            }

            // prompt to ask for continue

            const prompt = require('prompt-sync')();
            console.log(`-- tx ${name} failed, error:`, err.message)
            const continueDeploy = prompt(`Tx ${name} failed, continue? [y/n]`);
            if (continueDeploy == 'y') {
                return null
            } else {
                throw err
            }
        }
    }

    async verifyProxy(proxyAddress: string) {
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
            // const proposal = await this.hre.defender.proposeUpgrade(futuresAdapterContractAddress, FuturesAdapter);
            // await this.verifyContractUsingDefender(proposal)
            const upgraded = await this.hre.upgrades.upgradeProxy(futuresAdapterContractAddress, FuturesAdapter, {unsafeAllowLinkedLibraries: true});
            console.log(`Starting verify upgrade futures gateway`)
            await this.verifyImplContract(upgraded.deployTransaction)
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

    async createChainlinkPriceFeed(args: CreateChainLinkPriceFeed) {
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

    async createBUSDTestnet() {
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

    async createBUSDBonus() {
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


    async createCoreVaultContracts(): Promise<{ usdp: USDP, plp: PLP, vaultUtils: VaultUtils, vaultPriceFeed: VaultPriceFeed, vault: Vault, plpManager: LpManager }> {
        const usdp = await this.deployNonUpgradeableContract<USDP>('USDP', [])
        const plp = await this.deployNonUpgradeableContract<PLP>('PLP', [])
        const vaultUtils = await this.deployNonUpgradeableContract<VaultUtils>('VaultUtils', [])
        const vaultPriceFeed = await this.deployNonUpgradeableContract<VaultPriceFeed>('VaultPriceFeed', [])
        await this.createVault(
            vaultUtils.address,
            vaultPriceFeed.address,
            usdp.address,
        )
        const vault = await this.getDeployedContract<Vault>('Vault')
        const plpManager = await this.deployNonUpgradeableContract<LpManager>('LpManager', [
            plp.address,
            usdp.address,
            vault.address,
            ethersE.constants.AddressZero,
            0
        ])
        return {
            usdp,
            plp,
            vaultUtils,
            vaultPriceFeed,
            vault,
            plpManager
        }

    }

    // eg name = bnbPriceFeed
    async createPriceFeed(name: string): Promise<PriceFeed> {
        const contract = await this.deployNonUpgradeableContract<PriceFeed>('PriceFeed', [], {
            contractId: name
        })
        return contract;
    }

    async createWrapableToken(name: string, symbol: string, decimals: number): Promise<WETH> {
        const contract = await this.deployNonUpgradeableContract<WETH>('WETH', [
            `Mock ${name}`, symbol, decimals
        ], {
            contractId: symbol
        })
        return contract;
    }

    async createMockToken(symbol: string, name: string, decimals: number): Promise<MockToken> {
        const initialAmount = ethersE.utils.parseEther("1000000");
        const contract = await this.deployNonUpgradeableContract<MockToken>('MockToken', [
            initialAmount, `Mock ${name}`, symbol, decimals
        ], {
            contractId: symbol
        })
        return contract;
    }

    getWhitelistedTokens(): Token<IExtraTokenConfig>[] {
        return this.contractConfig.getStageConfig('whitelist')
    }

    async setConfigVaultToken(token: Token<IExtraTokenConfig>, isSkipExists?: boolean) {
        const vaultContract = await this.getDeployedContract<Vault>('Vault')
        if (isSkipExists) {
            // check before set
            const tokenConfig = await vaultContract.tokenConfigurations(token.address)
            // TODO check changes
            if (tokenConfig.isWhitelisted) {
                console.log(`Token ${token.address} already set`)
                return
            }
        }

        const {vaultTokenConfig} = token.extraConfig

        await this.waitTx(
            vaultContract.setConfigToken(
                token.address,
                token.decimals,
                vaultTokenConfig.mintProfitBps,
                vaultTokenConfig.tokenWeight,
                ethersE.utils.parseEther(vaultTokenConfig.maxUsdpAmount.toString()),
                vaultTokenConfig.isStableToken,
                vaultTokenConfig.isShortable
            ),
            `vault.setConfigToken ${token.symbol}`
        )


    }

    async createDptpFuturesGateway(args: CreateDptpFuturesGateway) {
        const contractName = "DptpFuturesGateway";
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                args.pcsId,
                args.pscCrossChainGateway,
                args.futuresAdapter,
                args.vault,
                args.weth,
                args.gatewayUtils,
                args.futurXGatewayStorage,
                args.executionFee,
            ];
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();
            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);
            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createGatewayUtils(vault: string, futurXGateway: string, gatewayStorage: string, futurXVoucher: string) {
        const contractName = 'GatewayUtils';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                vault,
                futurXGateway,
                gatewayStorage,
                futurXVoucher
            ];
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();
            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);
            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createReferralStorage() {
        const contractName = 'ReferralStorage';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const instance = await this.hre.upgrades.deployProxy(factory,);
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();
            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);
            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createVault(vaultUtilsAddress: string, vaultPriceFeedAddress: string, usdpAddress: string) {
        const contractName = 'Vault';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                vaultUtilsAddress,
                vaultPriceFeedAddress,
                usdpAddress,
            ];
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();
            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);
            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createReferralRewardTracker(arg: CreateReferralRewardTracker) {
        const contractName = 'ReferralRewardTracker';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                arg.rewardToken,
                arg.tokenDecimal,
                arg.referralStorage,
            ];
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();
            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);
            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createFuturXVoucher(futurXGateway: string, signer: string) {
        const contractName = 'FuturXVoucher';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                futurXGateway,
                signer
            ]
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();

            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);

            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }

    async createFuturXGatewayStorage(futurXGateway: string) {
        const contractName = 'FuturXGatewayStorage';
        const factory = await this.hre.ethers.getContractFactory(contractName);
        const contractAddress = await this.db.findAddressByKey(contractName);
        if (contractAddress) {
            const upgraded = await this.hre.upgrades.upgradeProxy(
                contractAddress,
                factory
            );
            console.log(`Starting verify upgrade ${contractName}`);
            await this.verifyImplContract(upgraded.deployTransaction);
            console.log(`Upgrade ${contractName}`);
        } else {
            const contractArgs = [
                futurXGateway
            ]
            const instance = await this.hre.upgrades.deployProxy(
                factory,
                contractArgs
            );
            console.log(`wait for deploy ${contractName}`);
            await instance.deployed();

            const address = instance.address.toString();
            console.log(`Address ${contractName}: ${address}`);

            await this.db.saveAddressByKey(contractName, address);
            await this.verifyProxy(address);
        }
    }
}
