import { expect, use } from "chai"
import { solidity } from "ethereum-waffle"
import { ethers } from "hardhat"
import { loadContractFixtures, loadMockTokenFixtures } from "../shared/fixtures"
import { VaultTracker } from "../shared/utilities"

use(solidity)

describe.only("Vault.buyUSDP", function() {
  it("should buy USDP failed", async function() {
    const {dummyToken, busd} = await loadMockTokenFixtures()
    const { vault, deployer, user1 } = await loadContractFixtures()
    await expect(vault.connect(user1).buyUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: caller not in whitelist")
    // white list caller
    await expect(vault.buyUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: token not in whitelist")

    await expect(vault.buyUSDP(busd.address, deployer.address)).to.be.revertedWith("Vault: transferIn token amount must be greater than 0")
  })

  it("should buy USDP success", async function() {
    const {busd, usdp, WETH} = await loadMockTokenFixtures()
    const { vault, deployer, setPrice} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, busd.address, deployer.address)
    await tracker.beforePurchase()
    // transfer to vault
    await busd.transfer(vault.address, ethers.utils.parseEther("100"))
    await setPrice(busd.address, 1)
    await vault.buyUSDP(busd.address, deployer.address)
    await tracker.expectAfter(
      {
        usdpBalanceDiff: 99,
        poolDataDiff: {
          feeReserve: 1,
          poolAmount: 99,
          usdpAmount: 99
        }
      }
    )

    // buy with ETH
    await setPrice(WETH.address, 1500)

    await tracker.beforePurchase(WETH.address)
    await WETH.transfer(vault.address, ethers.utils.parseEther("1"))
    await vault.buyUSDP(WETH.address, deployer.address)
    await tracker.expectAfter(
      {
        usdpBalanceDiff: 1485,
        poolDataDiff: {
          feeReserve: 15,
          poolAmount: 1485,
          usdpAmount: 1485
        }
      }
    )

    

  })

  it("Should buy USDP with token decimals < 18", async function() {
    // usdt has 9 decimals
    const {usdt, usdp} = await loadMockTokenFixtures()
    const { vault, deployer, setPrice} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, usdt.address, deployer.address)
    await tracker.beforePurchase()
    // transfer to vault
    await usdt.transfer(vault.address, ethers.utils.parseEther("100"))

    await setPrice(usdt.address, 1)
    await vault.buyUSDP(usdt.address, deployer.address)
    await tracker.expectAfter(
      {
        usdpBalanceDiff: 99,
        poolDataDiff: {
          feeReserve: 1,
          poolAmount: 99,
          usdpAmount: 99
        }
      }
    )

  })


})


