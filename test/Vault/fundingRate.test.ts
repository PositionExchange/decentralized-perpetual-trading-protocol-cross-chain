import { expect } from "chai"
import { ethers } from "hardhat"
import { MockToken } from "../../typeChain"
import {getBnbConfig, getBtcConfig, getDaiConfig} from "../shared/config"
import { loadContractFixtures, loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import { toChainlinkPrice, VaultTracker } from "../shared/utilities"
import {sleep} from "../../scripts/helper";

function bigNumberify(n) {
  return ethers.BigNumber.from(n)
}

function expandDecimals(n, decimals) {
  return bigNumberify(n).mul(bigNumberify(10).pow(decimals))
}

function toUsd(value) {
  const normalizedValue = parseInt(String(value * Math.pow(10, 10)))
  return ethers.BigNumber.from(normalizedValue).mul(ethers.BigNumber.from(10).pow(20))
}
describe("Vault.fundingRate", function() {

  it("funding rate", async () => {
    const {btc, btcPriceFeed, usdp } = await loadMockTokenFixtures()
    const {vault} = await loadVaultPureFixtures()
    const [wallet] = await ethers.getSigners()
    const user0 = wallet
    const user1 = wallet
    const user2 = wallet
    // @ts-ignore
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

    await vault.setFundingRate(1,600,600)

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000))
    // @ts-ignore
    await vault.setConfigToken(...getBtcConfig(btc))

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(41000))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000))

    await btc.mint(user1.address, expandDecimals(1, 8))
    await btc.connect(user1).transfer(vault.address, 250000) // 0.0025 BTC => 100 USD
    await vault.buyUSDP(btc.address, user1.address)

    await btc.mint(user0.address, expandDecimals(1, 8))
    await btc.connect(user1).transfer(vault.address, 25000) // 0.00025 BTC => 10 USD
    await expect(vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(110), true,0))
        .to.be.revertedWith("Vault: reservedAmount exceeded poolAmount")

    await sleep(100)
    await vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(50), true,0)
    // console.log("vault info after 1st increase", await vault.vaultInfo(btc.address))

    await sleep(100)
    await vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(50), true,0)
    // console.log("vault info after 2nd increase", await vault.vaultInfo(btc.address))
    // console.log("btc price", await btcPriceFeed.latestAnswer())

    await sleep(100)
    await vault.connect(user0).decreasePosition(user0.address, btc.address, btc.address, toUsd(50), true,user0.address,toUsd(50),0)
    // console.log("vault info after 1st decrease", await vault.vaultInfo(btc.address))
    // console.log("btc price", await btcPriceFeed.latestAnswer())

    const fundingRate = await vault.cumulativeFundingRates(btc.address)
    await expect(fundingRate.toString()).eq("819")
  })

})

