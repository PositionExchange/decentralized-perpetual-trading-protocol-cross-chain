import { expect } from "chai"
import { ethers } from "hardhat"
import {getBtcConfig} from "../shared/config"
import {loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import {expandDecimals, toChainlinkPrice, toUsd} from "../shared/utilities"
import {sleep} from "../../scripts/helper";

// TODO: Un-skip later
describe.skip("Vault.borrowingRate", function() {

  it("borrowing rate", async () => {
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
        0, // _minProfitTime
        true // _hasDynamicFees
    )

    await vault.setBorrowingRate(1,600,600)

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

    await sleep(1000)
    await vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(50), true,0)
    const positionKey = ethers.utils.solidityKeccak256(["address","address","address","bool"],[user0.address,btc.address,btc.address,true])
    const positionInfo1stIncrease = await vault.positionInfo(positionKey)
    expect(positionInfo1stIncrease.entryBorrowingRates.toString()).to.be.equal('0')

    await sleep(1000)
    await vault.connect(user0).increasePosition(user0.address, btc.address, btc.address, toUsd(50), true,0)
    const positionInfo2ndIncrease = await vault.positionInfo(positionKey)
    expect(positionInfo2ndIncrease.entryBorrowingRates.toString()).to.be.equal('273')

    await sleep(1000)
    await vault.connect(user0).decreasePosition(user0.address, btc.address, btc.address, toUsd(50), true,user0.address,toUsd(50),0)
    const positionInfo1stDecrease = await vault.positionInfo(positionKey)
    expect(positionInfo1stDecrease.entryBorrowingRates.toString()).to.be.equal('819')
  })

})

