import {MigrationContext, MigrationDefinition} from "../types";
import {LpManager, PLP, RewardRouter, VaultUtilsSplit} from "../../typeChain";
import {Token} from "../shared/types";
import {ethers} from "ethers";

//verify contracts/token/posi/POSI.sol:POSI
//

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => {
      const sendTxn = ctx.factory.waitTx
      const deployContract = <T extends ethers.Contract>(name: string, args: any[], opts: {contractId?: string} = {}) => {
          return ctx.factory.deployNonUpgradeableContract<T>(name, args, opts)
      }
      const nativeToken = ctx.factory.contractConfig.getStageConfig<typeof Token>('native_token')
      return {
        'deploy reward router': async () => {
          const vestingDuration = 365 * 24 * 60 * 60

            const glpManager = await ctx.factory.getDeployedContract<LpManager>('LpManager')
            const glp = await ctx.factory.getDeployedContract<PLP>('PLP')

            const posi = await deployContract("POSI", []);
            const esPosi = await deployContract("EsPOSI",[]);
            const bnPosi = await deployContract("MintableBaseToken", ["Bonus POSI", "bnPOSI", 0]);

            await sendTxn(esPosi.setInPrivateTransferMode(true), "esPosi.setInPrivateTransferMode")
            await sendTxn(glp.setInPrivateTransferMode(true), "glp.setInPrivateTransferMode")

            const stakedPosiTracker = await deployContract("RewardTracker", ["Staked POSI", "sPOSI"], {
              contractId: 'StakedPosiTracker'
            })
            const stakedPosiDistributor = await deployContract("RewardDistributor", [esPosi.address, stakedPosiTracker.address], {
              contractId: 'StakedPosiDistributor'
            })
            await sendTxn(stakedPosiTracker.initialize([posi.address, esPosi.address], stakedPosiDistributor.address), "stakedPosiTracker.initialize")
            await sendTxn(stakedPosiDistributor.updateLastDistributionTime(), "stakedPosiDistributor.updateLastDistributionTime")

            const bonusPosiTracker = await deployContract("RewardTracker", ["Staked + Bonus POSI", "sbPOSI"], {
              contractId: 'BonusPosiTracker'
            })
            const bonusPosiDistributor = await deployContract("BonusDistributor", [bnPosi.address, bonusPosiTracker.address], {
              contractId: 'BonusPosiDistributor'
            })
            await sendTxn(bonusPosiTracker.initialize([stakedPosiTracker.address], bonusPosiDistributor.address), "bonusPosiTracker.initialize")
            await sendTxn(bonusPosiDistributor.updateLastDistributionTime(), "bonusPosiDistributor.updateLastDistributionTime")

            const feePosiTracker = await deployContract("RewardTracker", ["Staked + Bonus + Fee POSI", "sbfPOSI"], {
              contractId: 'FeePosiTracker'
            })
            const feePosiDistributor = await deployContract("RewardDistributor", [nativeToken.address, feePosiTracker.address], {
              contractId: 'FeePosiDistributor'
            })
            await sendTxn(feePosiTracker.initialize([bonusPosiTracker.address, bnPosi.address], feePosiDistributor.address), "feePosiTracker.initialize")
            await sendTxn(feePosiDistributor.updateLastDistributionTime(), "feePosiDistributor.updateLastDistributionTime")

            const feePlpTracker = await deployContract("RewardTracker", ["Fee PLP", "fPLP"], {
              contractId: 'FeePlpTracker'
            })
            const feePlpDistributor = await deployContract("RewardDistributor", [nativeToken.address, feePlpTracker.address], {
              contractId: 'FeePlpDistributor'
            })
            await sendTxn(feePlpTracker.initialize([glp.address], feePlpDistributor.address), "feePlpTracker.initialize")
            await sendTxn(feePlpDistributor.updateLastDistributionTime({gasLimit: 100000}), "feePlpDistributor.updateLastDistributionTime")

            const stakedPlpTracker = await deployContract("RewardTracker", ["Fee + Staked PLP", "fsPLP"], {
              contractId: 'StakedPlpTracker'
            })
            const stakedPlpDistributor = await deployContract("RewardDistributor", [esPosi.address, stakedPlpTracker.address], {
              contractId: 'StakedPlpDistributor'
            })
            await sendTxn(stakedPlpTracker.initialize([feePlpTracker.address], stakedPlpDistributor.address), "stakedPlpTracker.initialize")
            await sendTxn(stakedPlpDistributor.updateLastDistributionTime({gasLimit: 100000}), "stakedPlpDistributor.updateLastDistributionTime")

            await sendTxn(stakedPosiTracker.setInPrivateTransferMode(true), "stakedPosiTracker.setInPrivateTransferMode")
            await sendTxn(stakedPosiTracker.setInPrivateStakingMode(true), "stakedPosiTracker.setInPrivateStakingMode")
            await sendTxn(bonusPosiTracker.setInPrivateTransferMode(true), "bonusPosiTracker.setInPrivateTransferMode")
            await sendTxn(bonusPosiTracker.setInPrivateStakingMode(true), "bonusPosiTracker.setInPrivateStakingMode")
            await sendTxn(bonusPosiTracker.setInPrivateClaimingMode(true), "bonusPosiTracker.setInPrivateClaimingMode")
            await sendTxn(feePosiTracker.setInPrivateTransferMode(true), "feePosiTracker.setInPrivateTransferMode")
            await sendTxn(feePosiTracker.setInPrivateStakingMode(true), "feePosiTracker.setInPrivateStakingMode")
            await sendTxn(feePlpTracker.setInPrivateTransferMode(true), "feePlpTracker.setInPrivateTransferMode")
            await sendTxn(feePlpTracker.setInPrivateStakingMode(true), "feePlpTracker.setInPrivateStakingMode")
            await sendTxn(stakedPlpTracker.setInPrivateTransferMode(true), "stakedPlpTracker.setInPrivateTransferMode")
            await sendTxn(stakedPlpTracker.setInPrivateStakingMode(true), "stakedPlpTracker.setInPrivateStakingMode")

            const gmxVester = await deployContract("Vester", [
              "Vested POSI", // _name
              "vPOSI", // _symbol
              vestingDuration, // _vestingDuration
              esPosi.address, // _esToken
              feePosiTracker.address, // _pairToken
              posi.address, // _claimableToken
              stakedPosiTracker.address, // _rewardTracker
            ], {
              contractId: 'VestedPOSI'
            })

            const glpVester = await deployContract("Vester", [
              "Vested PLP", // _name
              "vPLP", // _symbol
              vestingDuration, // _vestingDuration
              esPosi.address, // _esToken
              stakedPlpTracker.address, // _pairToken
              posi.address, // _claimableToken
              stakedPlpTracker.address, // _rewardTracker
            ], {
              contractId: 'vestedPLP'
            })

            const rewardRouter = await deployContract<RewardRouter>("RewardRouter", [
              nativeToken.address,
              posi.address,
              esPosi.address,
              bnPosi.address,
              glp.address
            ])
            await sendTxn(rewardRouter.initialize(
              stakedPosiTracker.address,
              bonusPosiTracker.address,
              feePosiTracker.address,
              feePlpTracker.address,
              stakedPlpTracker.address,
              glpManager.address,
              gmxVester.address,
              glpVester.address
            ), "rewardRouter.initialize")

            await sendTxn(glpManager.setHandler(rewardRouter.address, true), "glpManager.setHandler(rewardRouter)")

            // allow rewardRouter to stake in stakedPosiTracker
            await sendTxn(stakedPosiTracker.setHandler(rewardRouter.address, true), "stakedPosiTracker.setHandler(rewardRouter)")
            // allow bonusPosiTracker to stake stakedPosiTracker
            await sendTxn(stakedPosiTracker.setHandler(bonusPosiTracker.address, true), "stakedPosiTracker.setHandler(bonusPosiTracker)")
            // allow rewardRouter to stake in bonusPosiTracker
            await sendTxn(bonusPosiTracker.setHandler(rewardRouter.address, true), "bonusPosiTracker.setHandler(rewardRouter)")
            // allow bonusPosiTracker to stake feePosiTracker
            await sendTxn(bonusPosiTracker.setHandler(feePosiTracker.address, true), "bonusPosiTracker.setHandler(feePosiTracker)")
            await sendTxn(bonusPosiDistributor.setBonusMultiplier(10000), "bonusPosiDistributor.setBonusMultiplier")
            // allow rewardRouter to stake in feePosiTracker
            await sendTxn(feePosiTracker.setHandler(rewardRouter.address, true), "feePosiTracker.setHandler(rewardRouter)")
            // allow stakedPosiTracker to stake esPosi
            await sendTxn(esPosi.setHandler(stakedPosiTracker.address, true), "esPosi.setHandler(stakedPosiTracker)")
            // allow feePosiTracker to stake bnPosi
            await sendTxn(bnPosi.setHandler(feePosiTracker.address, true), "bnPosi.setHandler(feePosiTracker")
            // allow rewardRouter to burn bnPosi
            await sendTxn(bnPosi.setMinter(rewardRouter.address, true), "bnPosi.setMinter(rewardRouter")

            // allow stakedPlpTracker to stake feePlpTracker
            await sendTxn(feePlpTracker.setHandler(stakedPlpTracker.address, true), "feePlpTracker.setHandler(stakedPlpTracker)")
            // allow feePlpTracker to stake glp
            await sendTxn(glp.setHandler(feePlpTracker.address, true), "glp.setHandler(feePlpTracker)")

            // allow rewardRouter to stake in feePlpTracker
            await sendTxn(feePlpTracker.setHandler(rewardRouter.address, true), "feePlpTracker.setHandler(rewardRouter)")
            // allow rewardRouter to stake in stakedPlpTracker
            await sendTxn(stakedPlpTracker.setHandler(rewardRouter.address, true), "stakedPlpTracker.setHandler(rewardRouter)")

            await sendTxn(esPosi.setHandler(rewardRouter.address, true), "esPosi.setHandler(rewardRouter)")
            await sendTxn(esPosi.setHandler(stakedPosiDistributor.address, true), "esPosi.setHandler(stakedPosiDistributor)")
            await sendTxn(esPosi.setHandler(stakedPlpDistributor.address, true), "esPosi.setHandler(stakedPlpDistributor)")
            await sendTxn(esPosi.setHandler(stakedPlpTracker.address, true), "esPosi.setHandler(stakedPlpTracker)")
            await sendTxn(esPosi.setHandler(gmxVester.address, true), "esPosi.setHandler(gmxVester)")
            await sendTxn(esPosi.setHandler(glpVester.address, true), "esPosi.setHandler(glpVester)")

            await sendTxn(esPosi.setMinter(gmxVester.address, true), "esPosi.setMinter(gmxVester)")
            await sendTxn(esPosi.setMinter(glpVester.address, true), "esPosi.setMinter(glpVester)")

            await sendTxn(gmxVester.setHandler(rewardRouter.address, true), "gmxVester.setHandler(rewardRouter)")
            await sendTxn(glpVester.setHandler(rewardRouter.address, true), "glpVester.setHandler(rewardRouter)")

            await sendTxn(feePosiTracker.setHandler(gmxVester.address, true), "feePosiTracker.setHandler(gmxVester)")
            await sendTxn(stakedPlpTracker.setHandler(glpVester.address, true), "stakedPlpTracker.setHandler(glpVester)")
        },

        'deploy-reward-reader': async ()=>{
          const reward_reader = await deployContract("RewardReader", []);
        },
        'deploy-reader': async ()=>{
          const reward_reader = await deployContract("Reader", []);
        },
        'deploy-vault-reader': async ()=>{
          const reward_reader = await deployContract("VaultReader", []);
        },

        'deploy-vault-utils-splits': async ()=>{
          const vault_utils_split = await deployContract("VaultUtilsSplit", []);
          const vaultUtilsSplit = await ctx.factory.getDeployedContract<VaultUtilsSplit>('VaultUtilsSplit')
          const vaultAddress = await ctx.db.findAddressByKey('Vault')
          await sendTxn(vaultUtilsSplit.setVault(vaultAddress), "vaultUtilsSplit.setVault")
        }
      }
    }
}

export default migrations
