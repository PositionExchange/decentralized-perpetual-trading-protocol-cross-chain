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

  async function purchaseUSDP(payTokenSymbol = 'busd', amount = 100, price = 1){
    const tokenFixtures = await loadMockTokenFixtures()
    const {busd, usdt, usdtPriceFeed, usdp, busdPriceFeed, wethPriceFeed, weth} = tokenFixtures
    const payToken = tokenFixtures[payTokenSymbol]
    if (!payToken) {
      throw new Error(`payTokenSymbol ${payTokenSymbol} not found`)
    }
    const { vault, deployer} = await loadContractFixtures()
    const tracker = new VaultTracker(vault, usdp, payToken.address, deployer.address)
    // buyUSDP
    await tracker.beforePurchase()
    await tokenFixtures[`${payTokenSymbol}PriceFeed`].setLatestAnswer(toChainlinkPrice(price))
    await payToken.transfer(vault.address, ethers.utils.parseEther(amount.toString()))
    await vault.buyUSDP(payToken.address, deployer.address)
    const feeForPool = amount * 100/10000;
    const usdpAmount = amount*price - feeForPool*price
    const poolAmount = amount - feeForPool
    await tracker.expectAfter(
      {
        usdpBalanceDiff: usdpAmount,
        poolDataDiff: {
          feeReserve: feeForPool,
          poolAmount: poolAmount,
          usdpAmount: usdpAmount
        }
      }
    )
    return {busd, usdp, busdPriceFeed, vault, deployer, tracker, weth, wethPriceFeed, payToken, usdt, usdtPriceFeed}
  }

  it("should sell USDP sucessfully", async function() {
    const {tracker, usdp, vault, deployer, busd} = await purchaseUSDP()
    
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
  // it("should sell USDP price decreased", async function() {
  //   const {tracker, usdp, vault, deployer, busd, busdPriceFeed} = await purchase100BUSDUSDP()
  //
  //   // now price decreased
  //   await busdPriceFeed.setLatestAnswer(toChainlinkPrice(0.95))
  //   // then sell
  //   await tracker.beforePurchase()
  //   // transfer usdp to vault
  //   await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
  //   await vault.sellUSDP(busd.address, deployer.address)
  //   // expect token should be increased 
  //   // sell fees is 1%
  //   await tracker.expectAfter(
  //     {
  //       usdpBalanceDiff: -99,
  //       underlyingBalanceDiff: 93.1095,
  //       poolDataDiff: {
  //         // fee increased
  //         feeReserve: 0.9405,
  //         poolAmount: -99,
  //         usdpAmount: -99
  //       }
  //     }
  //   )
  //
  // })
  // sell USDP price increased
  it("should sell USDP price increased", async function() {
    const {tracker, usdp, vault, deployer, busd, busdPriceFeed} = await purchaseUSDP()

    // now price increased
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1.2))
    // then sell
    await tracker.beforePurchase()
    // transfer usdp to vault
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    await vault.sellUSDP(busd.address, deployer.address)
    // expect token should be increased 
    // sell fees is 1%
    await tracker.expectAfter(
      {
        usdpBalanceDiff: -99,
        underlyingBalanceDiff: 81.675,
        poolDataDiff: {
          // fee increased
          feeReserve: 0.825,
          poolAmount: -82.5,
          usdpAmount: -99
        }
      }
    )
  })
  // Sell USDP for base token
  it("should sell USDP (BUSD) for unstable token (WETH) token", async function() {
    const {tracker, usdp, vault, deployer, busd, wethPriceFeed, weth} = await purchaseUSDP()
    await wethPriceFeed.setLatestAnswer(toChainlinkPrice(1500))

    // user 1 purchase usdp using weth ensure that the pool will have ETH
    await weth.transfer(vault.address, ethers.utils.parseEther("1"))
    const [,user1] = await ethers.getSigners()
    await vault.setWhitelistCaller(user1.address, true)
    await vault.connect(user1).buyUSDP(weth.address, user1.address)

    // then sell
    await tracker.beforePurchase(weth.address)
    // transfer usdp to vault
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    // sell for WETH
    await vault.sellUSDP(weth.address, deployer.address)
    // expect token should be increased 
    // sell fees is 1%
    await tracker.expectAfter(
      {
        usdpBalanceDiff: -99,
        underlyingBalanceDiff: 0.06534,
        poolDataDiff: {
          // fee increased
          feeReserve: 0.00066,
          poolAmount: -0.066,
          usdpAmount: -99
        }
      }
    )
  })
  // Sell USDP WETH for stable tokens
  it("should sell USDP WETH for stable tokens", async function() {
    const {tracker, usdp, vault, deployer, busd, wethPriceFeed, busdPriceFeed, weth} = await purchaseUSDP('weth', 1, 1500)
    await wethPriceFeed.setLatestAnswer(toChainlinkPrice(1500))
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1))

    // user 1 purchase usdp using busd ensure that the pool will have BUSD
    const [,user1] = await ethers.getSigners()
    await busd.transfer(user1.address, ethers.utils.parseEther("5000"))
    await busd.connect(user1).transfer(vault.address, ethers.utils.parseEther("5000"))
    await vault.setWhitelistCaller(user1.address, true)
    await vault.connect(user1).buyUSDP(busd.address, user1.address)

    console.log("after user 1 purchase")

    // then sell
    await tracker.beforePurchase(weth.address)
    // transfer usdp to vault
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    // sell for WETH
    await vault.sellUSDP(weth.address, deployer.address)
    // expect token should be increased 
    // sell fees is 1%
    await tracker.expectAfter(
      {
        usdpBalanceDiff: -99,
        underlyingBalanceDiff: 0.06534,
        poolDataDiff: {
          // fee increased
          feeReserve: 0.00066,
          poolAmount: -0.066,
          usdpAmount: -99
        }
      }
    )
  })

  it("should sell USDP for stable tokens adjusted decimals", async function() {
    const {tracker, usdtPriceFeed, usdt, usdp, vault, deployer, busd, busdPriceFeed} = await purchaseUSDP()

    // user 1 purchase usdp using usudt ensure that the pool will have usdt
    await usdtPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    const [,user1] = await ethers.getSigners()
    await usdt.transfer(user1.address, ethers.utils.parseEther("5000"))
    await usdt.connect(user1).transfer(vault.address, ethers.utils.parseEther("5000"))
    await vault.setWhitelistCaller(user1.address, true)
    await vault.connect(user1).buyUSDP(usdt.address, user1.address)

   console.log("after user 1 purchase")

    // then sell
    await tracker.beforePurchase(usdt.address)
    // transfer usdp to vault
    await usdp.transfer(vault.address, ethers.utils.parseEther("99"))
    // sell for WETH
    await vault.sellUSDP(usdt.address, deployer.address)
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
  })
})


