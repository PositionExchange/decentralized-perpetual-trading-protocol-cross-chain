import { expect } from "chai"
import { ethers } from "hardhat"
import { MockToken } from "../../typeChain"
import { getBnbConfig, getDaiConfig } from "../shared/config"
import { loadContractFixtures, loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import { toChainlinkPrice, VaultTracker } from "../shared/utilities"

describe("Vault.getFeesBasisPoint", function() {

  it("getFeeBasisPoints", async () => {
    const {bnb, dai, bnbPriceFeed, daiPriceFeed, usdp } = await loadMockTokenFixtures()
    const {vault} = await loadVaultPureFixtures()
    const [wallet] = await ethers.getSigners()
    const user0 = wallet
    // const tracker = new VaultTracker(vault, usdp, bnb.address, user0.address)
    // await tracker.init()
    const bnbConfig = getBnbConfig(bnb, 10000)
    await vault.setFees(
      50, // _taxBasisPoints
      10, // _stableTaxBasisPoints
      20, // _mintBurnFeeBasisPoints
      30, // _swapFeeBasisPoints
      4, // _stableSwapFeeBasisPoints
      10, // _marginFeeBasisPoints
      (5), // _liquidationFeeUsd
      0, // _minProfitTime
      true // _hasDynamicFees
    )

    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(0)

    await bnb.mint(vault.address, 100)
    await vault.connect(user0).buyUSDP(bnb.address, wallet.address)

    expect(await vault.usdpAmount(bnb.address)).eq(29700)
    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(29700)

    // usdgAmount(bnb) is 29700, targetAmount(bnb) is 29700
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(100)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(104)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(100)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(104)

    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, true)).eq(51)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, true)).eq(58)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, false)).eq(51)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, false)).eq(58)

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    // @ts-ignore
    await vault.setConfigToken(...getDaiConfig(dai, 10000))

    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(14850)
    expect(await vault.getTargetUsdpAmount(dai.address)).eq(14850)

    // usdgAmount(bnb) is 29700, targetAmount(bnb) is 14850
    // incrementing bnb has an increased fee, while reducing bnb has a decreased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(50)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(50)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, false)).eq(50)
    expect(await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, false)).eq(50)
    expect(await vault.getFeeBasisPoints(bnb.address, 25000, 100, 50, false)).eq(50)
    expect(await vault.getFeeBasisPoints(bnb.address, 100000, 100, 50, false)).eq(150)


    // await tracker.init({newUnderlyingTokenAddress: dai.address})
    const usdpBefore = await usdp.balanceOf(user0.address)
    await dai.mint(vault.address, 20000)
    await vault.connect(user0).buyUSDP(dai.address, wallet.address)
    const usdpAfter = await usdp.balanceOf(user0.address)

    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(24850)
    expect(await vault.getTargetUsdpAmount(dai.address)).eq(24850)

    bnbConfig[3] = 30000
    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)

    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(37275)
    expect(await vault.getTargetUsdpAmount(dai.address)).eq(12425)

    expect(await vault.usdpAmount (bnb.address)).eq(29700)

    // usdgAmount(bnb) is 29700, targetAmount(bnb) is 37270
    // incrementing bnb has a decreased fee, while reducing bnb has an increased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(90)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(90)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(90)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(110)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(113)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, false)).eq(116)

    bnbConfig[3] = 5000
    // @ts-ignore
    await vault.setConfigToken(...bnbConfig)

    await bnb.mint(vault.address, 200)
    await vault.connect(user0).buyUSDP(bnb.address, wallet.address)

    expect(await vault.usdpAmount (bnb.address)).eq(89100)
    expect(await vault.getTargetUsdpAmount(bnb.address)).eq(36366)
    expect(await vault.getTargetUsdpAmount(dai.address)).eq(72733)

    // usdgAmount(bnb) is 88800, targetAmount(bnb) is 36266
    // incrementing bnb has an increased fee, while reducing bnb has a decreased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(28)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(28)
    expect(await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, false)).eq(28)
    expect(await vault.getFeeBasisPoints(bnb.address, 50000, 100, 50, false)).eq(28)
    expect(await vault.getFeeBasisPoints(bnb.address, 80000, 100, 50, false)).eq(28)

    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 50, 100, true)).eq(150)
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, false)).eq(0)
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, false)).eq(0)
    expect(await vault.getFeeBasisPoints(bnb.address, 20000, 50, 100, false)).eq(0)
    expect(await vault.getFeeBasisPoints(bnb.address, 50000, 50, 100, false)).eq(0)
  })

})

