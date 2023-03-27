import { expect, use } from "chai"
import { solidity } from "ethereum-waffle"
import { ethers } from "hardhat"
import { LpManager, PLP, PriceFeed, USDP, Vault, VaultPriceFeed } from "../../typeChain"
import { getBnbConfig, getBtcConfig, getEthConfig } from "../shared/config"
import { deployContractFixtures, deployVaultPureFixtures, loadContractFixtures, loadMockTokenFixtures } from "../shared/fixtures"
import { deployContract, expandDecimals, toChainlinkPrice, VaultTracker } from "../shared/utilities"

use(solidity)

describe("Vault.swap", function() {
  const provider = ethers.provider
  let [wallet, user0, user1, user2, user3] = [] as any[]
  let vault: Vault
  let vaultPriceFeed: VaultPriceFeed
  let usdp: USDP
  let router
  let bnb
  let bnbPriceFeed: PriceFeed
  let btc
  let btcPriceFeed: PriceFeed
  let eth
  let ethPriceFeed: PriceFeed
  let dai
  let daiPriceFeed: PriceFeed
  let distributor0
  let yieldTracker0
  let lpManager: LpManager
  let plp: PLP
  beforeEach(async () => {
    const tokenFixtures = await loadMockTokenFixtures()
    const contractFixtures = await deployVaultPureFixtures()
    dai = tokenFixtures.dai
    bnbPriceFeed = tokenFixtures.bnbPriceFeed
    daiPriceFeed = tokenFixtures.daiPriceFeed
    btc = tokenFixtures.btc
    usdp = tokenFixtures.usdp
    plp = tokenFixtures.plp
    bnb = tokenFixtures.bnb
    eth = tokenFixtures.eth
    btcPriceFeed = tokenFixtures.btcPriceFeed
    vault = contractFixtures.vault
    lpManager = contractFixtures.lpManager
    vaultPriceFeed = contractFixtures.vaultPriceFeed
    ethPriceFeed = tokenFixtures.wethPriceFeed
    const users = await ethers.getSigners()
    wallet = users[0]
    user0 = users[1]
    user1 = users[2]
    user2 = users[3]
    user3 = users[4]
    await vault.setFees(
      50, // _taxBasisPoints
      10, // _stableTaxBasisPoints
      30, // _mintBurnFeeBasisPoints
      30, // _swapFeeBasisPoints
      4, // _stableSwapFeeBasisPoints
      10, // _marginFeeBasisPoints
      (5), // _liquidationFeeUsd
      0, // _minProfitTime
      false// _hasDynamicFees
    )

    distributor0 = await deployContract("TimeDistributor", [])
    yieldTracker0 = await deployContract("YieldTracker", [usdp.address])

    await yieldTracker0.setDistributor(distributor0.address)
    await distributor0.setDistribution([yieldTracker0.address], [1000], [bnb.address])

    await bnb.mint(distributor0.address, 5000)
    await usdp.setYieldTrackers([yieldTracker0.address])

    await vaultPriceFeed.setPriceFeedConfig(bnb.address, bnbPriceFeed.address, 8, 0, false)
    await vaultPriceFeed.setPriceFeedConfig(btc.address, btcPriceFeed.address, 8, 0, false)
    await vaultPriceFeed.setPriceFeedConfig(eth.address, ethPriceFeed.address, 8, 0, false)
    
    await vaultPriceFeed.setPriceFeedConfig(dai.address, daiPriceFeed.address, 8, 0, false)
  })
  it("swap", async () => {
    await expect(vault.connect(user1).swap(bnb.address, btc.address, user2.address))
      .to.be.revertedWith("Vault: token not in whitelist")

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    // @ts-ignore
    await vault.setConfigToken(...getBnbConfig(bnb))
    await expect(vault.connect(user1).swap(bnb.address, btc.address, user2.address))
      .to.be.revertedWith("Vault: token not in whitelist")

    await expect(vault.connect(user1).swap(bnb.address, bnb.address, user2.address))
      .to.be.revertedWith("Vault: invalid tokens")

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    // @ts-ignore
    await vault.setConfigToken(...getBtcConfig(btc))

    await vault.setIsSwapEnabled(false)
    await expect(vault.connect(user1).swap(bnb.address, btc.address, user2.address))
      .to.be.revertedWith("Vault: swap is not supported")

    await vault.setIsSwapEnabled(true)

    await bnb.mint(user0.address, expandDecimals(200, 18))
    await btc.mint(user0.address, expandDecimals(1, 8))

    expect(await lpManager.getAumInUsdp(false)).eq(0)

    await bnb.connect(user0).transfer(vault.address, expandDecimals(200, 18))
    await vault.connect(user0).buyUSDP(bnb.address, user0.address)

    expect(await lpManager.getAumInUsdp(false)).eq(expandDecimals(59820, 18)) // 60,000 * 99.7%

    await btc.connect(user0).transfer(vault.address, expandDecimals(1, 8))
    await vault.connect(user0).buyUSDP(btc.address, user0.address)

    expect(await lpManager.getAumInUsdp(false)).eq(expandDecimals(119640, 18)) // 59,820 + (60,000 * 99.7%)

    expect(await usdp.balanceOf(user0.address)).eq(expandDecimals(120000, 18).sub(expandDecimals(360, 18))) // 120,000 * 0.3% => 360

    expect(await vault.feeReserves(bnb.address)).eq("600000000000000000") // 200 * 0.3% => 0.6
    expect(await vault.usdgAmounts(bnb.address)).eq(expandDecimals(200 * 300, 18).sub(expandDecimals(180, 18))) // 60,000 * 0.3% => 180
    expect(await vault.poolAmounts(bnb.address)).eq(expandDecimals(200, 18).sub("600000000000000000"))

    expect(await vault.feeReserves(btc.address)).eq("300000") // 1 * 0.3% => 0.003
    expect(await vault.usdgAmounts(btc.address)).eq(expandDecimals(200 * 300, 18).sub(expandDecimals(180, 18)))
    expect(await vault.poolAmounts(btc.address)).eq(expandDecimals(1, 8).sub("300000"))

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500))

    expect(await lpManager.getAumInUsdp(false)).eq(expandDecimals(139580, 18)) // 59,820 / 300 * 400 + 59820

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(90000))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(100000))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(80000))

    expect(await lpManager.getAumInUsdp(false)).eq(expandDecimals(159520, 18)) // 59,820 / 300 * 400 + 59820 / 60000 * 80000

    await bnb.mint(user1.address, expandDecimals(100, 18))
    await bnb.connect(user1).transfer(vault.address, expandDecimals(100, 18))

    expect(await btc.balanceOf(user1.address)).eq(0)
    expect(await btc.balanceOf(user2.address)).eq(0)

    console.log("swap.test.ts:117", "start swap");
    
    const tx = await vault.connect(user1).swap(bnb.address, btc.address, user2.address)
    // await reportGasUsed(provider, tx, "swap gas used")

    expect(await lpManager.getAumInUsdp(false)).eq(expandDecimals(167520, 18)) // 159520 + (100 * 400) - 32000

    expect(await btc.balanceOf(user1.address)).eq(0)
    expect(await btc.balanceOf(user2.address)).eq(expandDecimals(4, 7).sub("120000")) // 0.8 - 0.0012

    expect(await vault.feeReserves(bnb.address)).eq("600000000000000000") // 200 * 0.3% => 0.6
    expect(await vault.usdgAmounts(bnb.address)).eq(expandDecimals(100 * 400, 18).add(expandDecimals(200 * 300, 18)).sub(expandDecimals(180, 18)))
    expect(await vault.poolAmounts(bnb.address)).eq(expandDecimals(100, 18).add(expandDecimals(200, 18)).sub("600000000000000000"))

    expect(await vault.feeReserves(btc.address)).eq("420000") // 1 * 0.3% => 0.003, 0.4 * 0.3% => 0.0012
    expect(await vault.usdgAmounts(btc.address)).eq(expandDecimals(200 * 300, 18).sub(expandDecimals(180, 18)).sub(expandDecimals(100 * 400, 18)))
    expect(await vault.poolAmounts(btc.address)).eq(expandDecimals(1, 8).sub("300000").sub(expandDecimals(4, 7))) // 59700000, 0.597 BTC, 0.597 * 100,000 => 59700

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(450))

    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await bnb.balanceOf(user3.address)).eq(0)
    await usdp.connect(user0).transfer(vault.address, expandDecimals(50000, 18))
    await vault.sellUSDP(bnb.address, user3.address)
    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await bnb.balanceOf(user3.address)).eq("99700000000000000000") // 99.7, 50000 / 500 * 99.7%

    await usdp.connect(user0).transfer(vault.address, expandDecimals(50000, 18))
    await vault.sellUSDP(btc.address, user3.address)

    await usdp.connect(user0).transfer(vault.address, expandDecimals(10000, 18))
    await expect(vault.sellUSDP(btc.address, user3.address))
      .to.be.revertedWith("Vault: poolAmount exceeded")
  })

  it("caps max USDP amount", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600))
    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000))

    const bnbConfig = getBnbConfig(bnb)
    const ethConfig = getBnbConfig(eth)

    bnbConfig[4] = expandDecimals(299000, 18)
    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)

    ethConfig[4] = expandDecimals(30000, 18)
    // @ts-ignore
    await vault.setConfigToken(...ethConfig)

    await bnb.mint(user0.address, expandDecimals(499, 18))
    await bnb.connect(user0).transfer(vault.address, expandDecimals(499, 18))
    await vault.connect(user0).buyUSDP(bnb.address, user0.address)

    await eth.mint(user0.address, expandDecimals(10, 18))
    await eth.connect(user0).transfer(vault.address, expandDecimals(10, 18))
    await vault.connect(user0).buyUSDP(eth.address, user1.address)

    await bnb.mint(user0.address, expandDecimals(1, 18))
    await bnb.connect(user0).transfer(vault.address, expandDecimals(1, 18))

    await expect(vault.connect(user0).buyUSDP(bnb.address, user0.address))
      .to.be.revertedWith("Vault: Max debt amount exceeded")

    bnbConfig[4] = expandDecimals(299100, 18)
    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)

    await vault.connect(user0).buyUSDP(bnb.address, user0.address)

    await bnb.mint(user0.address, expandDecimals(1, 18))
    await bnb.connect(user0).transfer(vault.address, expandDecimals(1, 18))
    await expect(vault.connect(user0).swap(bnb.address, eth.address, user1.address))
      .to.be.revertedWith("Vault: Max debt amount exceeded")

    bnbConfig[4] = expandDecimals(299700, 18)
    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)
    await vault.connect(user0).swap(bnb.address, eth.address, user1.address)
  })

  it("does not cap max USDP debt", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600))
    //@ts-ignore
    await vault.setConfigToken(...getBnbConfig(bnb))

    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000))
    //@ts-ignore
    await vault.setConfigToken(...getEthConfig(eth))

    await bnb.mint(user0.address, expandDecimals(100, 18))
    await bnb.connect(user0).transfer(vault.address, expandDecimals(100, 18))
    await vault.connect(user0).buyUSDP(bnb.address, user0.address)

    await eth.mint(user0.address, expandDecimals(10, 18))

    expect(await eth.balanceOf(user0.address)).eq(expandDecimals(10, 18))
    expect(await bnb.balanceOf(user1.address)).eq(0)

    await eth.connect(user0).transfer(vault.address, expandDecimals(10, 18))
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address)

    expect(await eth.balanceOf(user0.address)).eq(0)
    expect(await bnb.balanceOf(user1.address)).eq("49850000000000000000")

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))

    await eth.mint(user0.address, expandDecimals(1, 18))
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18))
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address)
  })

  it("ensures poolAmount >= buffer", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600))
    // @ts-ignore
    await vault.setConfigToken(...getBnbConfig(bnb))

    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000))
    // @ts-ignore
    await vault.setConfigToken(...getEthConfig(eth))

    await bnb.mint(user0.address, expandDecimals(100, 18))
    await bnb.connect(user0).transfer(vault.address, expandDecimals(100, 18))
    await vault.connect(user0).buyUSDP(bnb.address, user0.address)

    await vault.setBufferAmount(bnb.address, "94700000000000000000") // 94.7

    expect(await vault.poolAmounts(bnb.address)).eq("99700000000000000000") // 99.7
    expect(await vault.poolAmounts(eth.address)).eq(0)
    expect(await bnb.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).eq(0)

    await eth.mint(user0.address, expandDecimals(1, 18))
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18))
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address)

    expect(await vault.poolAmounts(bnb.address)).eq("94700000000000000000") // 94.7
    expect(await vault.poolAmounts(eth.address)).eq(expandDecimals(1, 18))
    expect(await bnb.balanceOf(user1.address)).eq("4985000000000000000") // 4.985
    expect(await eth.balanceOf(user1.address)).eq(0)

    await eth.mint(user0.address, expandDecimals(1, 18))
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18))
    await expect(vault.connect(user0).swap(eth.address, bnb.address, user1.address))
      .to.be.revertedWith("Vault: insufficient pool amount")
  })
})

