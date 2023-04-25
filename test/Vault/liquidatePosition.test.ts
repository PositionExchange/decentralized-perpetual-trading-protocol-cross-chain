import { expect } from "chai"
import { ethers } from "hardhat"
import {getBtcConfig} from "../shared/config"
import { loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import {expandDecimals, toChainlinkPrice, toUsd} from "../shared/utilities"
describe("Vault.liquidatePosition", function() {

  it("given valid request, should success", async () => {
    const {btc, btcPriceFeed} = await loadMockTokenFixtures()
    const {vault} = await loadVaultPureFixtures()
    const [wallet] = await ethers.getSigners()
    const user1 = wallet
    const user0 = wallet
    // @ts-ignore
    await vault.setFees(
        50, // _taxBasisPoints
        10, // _stableTaxBasisPoints
        20, // _mintBurnFeeBasisPoints
        30, // _swapFeeBasisPoints
        4, // _stableSwapFeeBasisPoints
        10, // _marginFeeBasisPoints
        0, // _minProfitTime
        true // _hasDynamicFees
    )
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

    await vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(90), 225000,true,0)
    const positionKey = ethers.utils.solidityKeccak256(["address","address","address","bool"],[user0.address,btc.address,btc.address,true])

    await vault.connect(user0).liquidatePosition(user0.address, btc.address, btc.address, toUsd(90), 90,true)
    const positionInfoAfterLiquidate = await vault.positionInfo(positionKey)
    expect(positionInfoAfterLiquidate.reservedAmount.toString()).eq("0")
  })

})

