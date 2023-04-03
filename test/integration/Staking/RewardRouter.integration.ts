import { expect } from 'chai'
import hre from 'hardhat'
// verify after contract deployed

import { ContractWrapperFactory } from "../../../deploy/ContractWrapperFactory"
import { ContractConfig } from '../../../deploy/shared/PreDefinedContractAddress'
import { loadDb } from '../../../deploy/shared/utils'
import { MockToken, RewardRouter, RewardTracker } from '../../../typeChain'
import { checkApprove, SimpleTokenBalanceTracker } from '../../shared/utilities'

const TEST_STAGE = 'test'

describe('Integration.Staking.RewardRouter', () => {
  let factory: ContractWrapperFactory
  let busd: MockToken
  let plp: MockToken
  let usdp: MockToken
  let rewardRouter: RewardRouter

  let feePlpTracker: RewardTracker
  let stakedPlpTracker: RewardTracker
  let simpleBalanceTracker: SimpleTokenBalanceTracker

  beforeEach(async () => {
    const [signer] = await hre.ethers.getSigners()
    const db = loadDb(TEST_STAGE)
        factory = new ContractWrapperFactory(db, hre, new ContractConfig(TEST_STAGE, hre.network.config.chainId, db))
    busd = await factory.getDeployedContract<MockToken>('BUSD', 'MockToken')
    plp = await factory.getDeployedContract<MockToken>('PLP')
    usdp = await factory.getDeployedContract<MockToken>('USDP')
    rewardRouter = await factory.getDeployedContract<RewardRouter>('RewardRouter')
    feePlpTracker = await factory.getDeployedContract<RewardTracker>('FeePlpTracker', 'RewardTracker')
    stakedPlpTracker = await factory.getDeployedContract<RewardTracker>('StakedPlpTracker', 'RewardTracker')
    simpleBalanceTracker = new SimpleTokenBalanceTracker([
      busd,
      feePlpTracker as unknown as MockToken,
      stakedPlpTracker as unknown as MockToken,
    ], signer.address, {
      [feePlpTracker.address]: 'stakedAmounts',
      [stakedPlpTracker.address]: 'stakedAmounts',
    })
  })

  it("should add liquidity & stake", async () => {
    const [user] = await hre.ethers.getSigners()
    const {plpManager} = await factory.createCoreVaultContracts()
    await checkApprove(busd, plpManager.address)
    console.log("start add liquidity");

    await simpleBalanceTracker.before()

    const tx = await rewardRouter.mintAndStakePlp(
      busd.address,
      hre.ethers.utils.parseEther("1"),
      hre.ethers.utils.parseEther("0.9"),
      hre.ethers.utils.parseEther("0.9"),
      // {
      //   gasLimit: 10000000
      // }
    ) 
    console.log("tx", tx.hash)
    await tx.wait()

    // check feePlpTracker
    // check stakedPlpTracker
    await simpleBalanceTracker.multiExpectAfter(
      {
        [feePlpTracker.address]: ['gte',("0.95")],
        [stakedPlpTracker.address]: ['gte',("0.95")],
      }
    )
  })

  it("should unstake & remove liquidity", async () => {
    const [user] = await hre.ethers.getSigners()
    const stakedAmount = await stakedPlpTracker.stakedAmounts(user.address)
    await simpleBalanceTracker.before()
    const tx = await rewardRouter.unstakeAndRedeemPlp(
      busd.address,
      stakedAmount,
      hre.ethers.utils.parseEther("0.9"),
      user.address
    )
    console.log("tx", tx.hash)
    await tx.wait()
    await simpleBalanceTracker.multiExpectAfter({
      [busd.address]: ['gte',"0.95"],
    })
  })

})

