import { expect } from 'chai'
import hre from 'hardhat'
// verify after contract deployed

import { ContractWrapperFactory } from "../../../deploy/ContractWrapperFactory"
import { ContractConfig } from '../../../deploy/shared/PreDefinedContractAddress'
import { loadDb } from '../../../deploy/shared/utils'
import { MockToken } from '../../../typeChain'

const TEST_STAGE = 'test'

async function checkApprove(token: MockToken, spender: string) {
  const [signer] = await hre.ethers.getSigners()
  const allowance = await token.allowance(signer.address, spender)
  if (allowance.eq(0)) {
    console.log("Approving");
    await token.approve(spender, hre.ethers.constants.MaxUint256)
  }else{
    console.log("Already approved");
    
  }
}

// should run in hardhat folk mode
describe('Intergration.vault.liquidity', () => {
  let factory: ContractWrapperFactory
  // mock token is ok even for mainnet, we just need the ERC20 interface
  let busd: MockToken
  let plp: MockToken
  let usdp: MockToken
  beforeEach(async () => {
    const [signer] = await hre.ethers.getSigners()
    const db = loadDb(TEST_STAGE)
    factory = new ContractWrapperFactory(db, hre, new ContractConfig(TEST_STAGE, hre.network.config.chainId, db))
    busd = await factory.getDeployedContract<MockToken>('BUSD', 'MockToken')
    plp = await factory.getDeployedContract<MockToken>('PLP')
    usdp = await factory.getDeployedContract<MockToken>('USDP')
  })

  it("Should add liquidity to vault", async () => {
    const [user] = await hre.ethers.getSigners()
    const {vault, plpManager} = await factory.createCoreVaultContracts()
    console.log("busd address", busd.address)
    await checkApprove(busd, plpManager.address)
    console.log("start add liquidity")
    const plpBalanceBefore = await plp.balanceOf(user.address)
    const usdpBalanceBefore = await usdp.balanceOf(plpManager.address)
    const tx = await plpManager.addLiquidity(
      busd.address,
      hre.ethers.utils.parseEther("1"),
      hre.ethers.utils.parseEther("0.9"),
      hre.ethers.utils.parseEther("0.9"),
      // {
      //   gasLimit: 2000000
      // }
    )
    console.log("Add liquidity tx", tx.hash)
    await tx.wait()
    // expect usdp, and plp balance > 0.9
    const usdpBalance = await usdp.balanceOf(plpManager.address)
    const plpBalance = await plp.balanceOf(user.address)
    expect(usdpBalance.sub(usdpBalanceBefore).gt(hre.ethers.utils.parseEther("0.9"))).to.be.true
    expect(plpBalance.sub(plpBalanceBefore).gt(hre.ethers.utils.parseEther("0.9"))).to.be.true
  })

  it("Should remove liquidity from vault", async () => {
    const [user] = await hre.ethers.getSigners()
    const {plpManager} = await factory.createCoreVaultContracts()
    console.log("start remove liquidity")
    const busdBalanceBefore = await busd.balanceOf(user.address)
    const usdpBalanceBefore = await usdp.balanceOf(plpManager.address)
    const tx = await plpManager.removeLiquidity(
      busd.address,
      hre.ethers.utils.parseEther("0.95"),
      hre.ethers.utils.parseEther("0.9"),
      user.address,
      // {
      //   gasLimit: 2000000
      // }
    )
    console.log("Remove liquidity tx", tx.hash)
    await tx.wait()
    // expect usdp, and plp balance > 0.9
    const usdpBalance = await usdp.balanceOf(plpManager.address)
    const busdBalance = await busd.balanceOf(user.address)
    console.log("diff usdp", usdpBalanceBefore.sub(usdpBalance).toString(), busdBalance.sub(busdBalanceBefore).toString())
    expect(usdpBalanceBefore.sub(usdpBalance).gt(hre.ethers.utils.parseEther("0.9"))).to.be.true
    expect(busdBalance.sub(busdBalanceBefore).gt(hre.ethers.utils.parseEther("0.9"))).to.be.true

  })

})
