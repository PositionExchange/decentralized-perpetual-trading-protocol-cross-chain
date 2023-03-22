import { expect, use } from "chai"
import { solidity } from "ethereum-waffle"
import { ethers } from "hardhat"
import { loadContractFixtures, loadMockTokenFixtures } from "../shared/fixtures"
import { VaultTracker } from "../shared/utilities"

use(solidity)


describe.only("Vault.sellUSDP", function() {
  it("should sell USDP failed", async function() {
    const {dummyToken, busd} = await loadMockTokenFixtures()
    const { vault, deployer, user1 } = await loadContractFixtures()
    await expect(vault.connect(user1).sellUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: caller not in whitelist")
    // white list caller
    await expect(vault.sellUSDP(dummyToken.address, deployer.address)).to.be.revertedWith("Vault: token not in whitelist")

    await expect(vault.sellUSDP(busd.address, deployer.address)).to.be.revertedWith("Vault: transferIn token amount must be greater than 0")
  })

  it("should sell USDP sucessfully", async function() {
    const {busd, usdp} = await loadMockTokenFixtures()
    const { vault, deployer, setPrice} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, busd.address, deployer.address)
    await setPrice(busd.address, 1)
    // buyUSDP
    await usdp.transfer(vault.address, ethers.utils.parseEther("100"))
    await vault.buyUSDP(busd.address, deployer.address)
    // then sell
    await tracker.beforePurchase()
    // transfer usdp to vault
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    await vault.sellUSDP(busd.address, deployer.address)
    // expect token should be increased 
    await tracker.expectAfter(
      {
        usdpBalanceDiff: -99,
        poolDataDiff: {
          feeReserve: -1,
          poolAmount: -99,
          usdpAmount: -99
        }
      }
    )


  })

})


