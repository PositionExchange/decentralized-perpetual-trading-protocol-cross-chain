import { expect } from "chai"
import { getDaiConfig } from "../shared/config"
import { loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import { expandDecimals, toChainlinkPrice } from "../shared/utilities"

describe("Vault.getPrice", function() {
  it("getPrice", async () => {
    const {dai, daiPriceFeed, busd, busdPriceFeed, btc, btcPriceFeed } = await loadMockTokenFixtures()
    const {vault, vaultPriceFeed} = await loadVaultPureFixtures()
    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    console.log("daiPriceFeed.latestAnswer", await daiPriceFeed.latestAnswer())

    // @ts-ignore
    await vault.setConfigToken(...getDaiConfig(dai))
    expect(await vaultPriceFeed.getPrice(dai.address, true)).eq(expandDecimals(1, 30))
    console.log("daiPriceFeed.latestAnswer ok")

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1.1))
    expect(await vaultPriceFeed.getPrice(dai.address, true)).eq(expandDecimals(11, 29))
    console.log("daiPriceFeed.latestAnswer2 ok")

    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await vault.setConfigToken(
      busd.address, // _token
      18, // _tokenDecimals
      75, // _minProfitBps,
      10000, // _tokenWeight
      0, // _maxUsdgAmount
      false, // _isStable
      true // _isShortable
    )

    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(1, 30))
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1.1))
    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(11, 29))

    await vaultPriceFeed.setMaxStrictPriceDeviation(expandDecimals(1, 29))
    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(1, 30))

    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(1.11))
    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(111, 28))
    expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(1, 30))

    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(0.9))
    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(111, 28))
    expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(1, 30))

    await vaultPriceFeed.setSpreadBasisPoints(busd.address, 20)
    expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(1, 30))

    await vaultPriceFeed.setSpreadBasisPoints(busd.address, 0)
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(0.89))
    await busdPriceFeed.setLatestAnswer(toChainlinkPrice(0.89))
    expect(await vaultPriceFeed.getPrice(busd.address, true)).eq(expandDecimals(1, 30))
    expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(89, 28))

    await vaultPriceFeed.setSpreadBasisPoints(busd.address, 20)
    expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(89, 28))

    // await vaultPriceFeed.setUseV2Pricing(true)
    // expect(await vaultPriceFeed.getPrice(busd.address, false)).eq(expandDecimals(89, 28))

    await vaultPriceFeed.setSpreadBasisPoints(btc.address, 0)
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000))
    expect(await vaultPriceFeed.getPrice(btc.address, true)).eq(expandDecimals(40000, 30))

    await vaultPriceFeed.setSpreadBasisPoints(btc.address, 20)
    expect(await vaultPriceFeed.getPrice(btc.address, false)).eq(expandDecimals(39920, 30))
  })

})
