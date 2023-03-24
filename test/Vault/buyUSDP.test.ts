import { expect, use } from "chai"
import { solidity } from "ethereum-waffle"
import { ethers } from "hardhat"
import { loadContractFixtures, loadMockTokenFixtures } from "../shared/fixtures"
import { toChainlinkPrice, VaultTracker } from "../shared/utilities"

use(solidity)

describe("Vault.buyUSDP", function() {
  it("should buy USDP failed", async function() {
    const {dummyToken, busd} = await loadMockTokenFixtures()
    const { vault, deployer, user1 } = await loadContractFixtures()
    await expect(vault.connect(user1).buyUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: caller not in whitelist")
    // white list caller
    await expect(vault.buyUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: token not in whitelist")

    await expect(vault.buyUSDP(busd.address, deployer.address)).to.be.revertedWith("Vault: transferIn token amount must be greater than 0")
  })

  it("should buy USDP success", async function() {
    const {busd, usdp, busdPriceFeed} = await loadMockTokenFixtures()
    const { vault, deployer} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, busd.address, deployer.address)
    await tracker.beforePurchase()
    // transfer to vault
    await busd.transfer(vault.address, ethers.utils.parseEther("100"))
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1))
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



  })
  it("Should buy USDP with not stable token", async function() {
    const {WETH, usdp, wethPriceFeed} = await loadMockTokenFixtures()
    const { vault, deployer} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, WETH.address, deployer.address)
    // buy with ETH
    console.log("set eth price")
    await tracker.beforePurchase(WETH.address)
    wethPriceFeed.setLatestAnswer(toChainlinkPrice("1500"))
    await WETH.transfer(vault.address, ethers.utils.parseEther("1"))
    console.log("after weth transfer", WETH.address)
    await vault.buyUSDP(WETH.address, deployer.address)
    await tracker.expectAfter(
      {
        usdpBalanceDiff: 1485,
        poolDataDiff: {
          feeReserve: 0.01,
          poolAmount: 0.99,
          usdpAmount: 1485
        }
      }
    )
  })

  it("Should buy USDP with token decimals < 18", async function() {
    // usdt has 9 decimals
    const {usdt, usdp, usdtPriceFeed} = await loadMockTokenFixtures()
    const { vault, deployer} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, usdt.address, deployer.address)
    await tracker.beforePurchase()
    usdtPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    // transfer to vault
    await usdt.transfer(vault.address, ethers.utils.parseEther("100"))
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


