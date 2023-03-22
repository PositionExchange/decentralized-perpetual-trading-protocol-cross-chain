import { expect, use } from "chai"
import { solidity } from "ethereum-waffle"
import { ethers } from "hardhat"
import { loadContractFixtures, loadMockTokenFixtures } from "../shared/fixtures"
import { toChainlinkPrice, VaultTracker } from "../shared/utilities"

use(solidity)


describe.only("Vault.sellUSDP", function() {
  it("should sell USDP failed", async function() {
    const {dummyToken, busd} = await loadMockTokenFixtures()
    const { vault, deployer, user1 } = await loadContractFixtures()
    await expect(vault.connect(user1).sellUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: caller not in whitelist")
    // white list caller
    await expect(vault.sellUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: token not in whitelist")

    await expect(vault.sellUSDP(busd.address, deployer.address)).to.be.revertedWith("Vault: invalid usdp amount")
  })

  it("should sell USDP sucessfully", async function() {
    const {busd, usdp, busdPriceFeed} = await loadMockTokenFixtures()
    const { vault, deployer} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, busd.address, deployer.address)
    // buyUSDP
    await tracker.beforePurchase()
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await busd.transfer(vault.address, ethers.utils.parseEther("100"))
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
    // then sell
    await tracker.beforePurchase()
    // transfer usdp to vault
    console.log("balance before", await usdp.balanceOf(deployer.address))
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    await vault.sellUSDP(busd.address, deployer.address)
    // expect token should be increased 
    // sell fees is 1%
    await tracker.expectAfter(
      {
        usdpBalanceDiff: -99,
        underlyingBalanceDiff: 98.01,
        poolDataDiff: {
          // increase 0.99
          feeReserve: 0.99,
          poolAmount: -99,
          usdpAmount: -99
        }
      }
    )
    // expect balance
  })

  // sell USDP price decreased
  // sell USDP price increased
  // Sell USDP for base token
  // Sell USDP WETH for stable tokens
  // Sell USDP for other tokens



})


