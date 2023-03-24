import { expect } from "chai"
import { getBnbConfig, getBtcConfig, getDaiConfig } from "./shared/config"
import { loadMockTokenFixtures, loadVaultPureFixtures } from "./shared/fixtures"
import { expandDecimals, getBlockTime, toChainlinkPrice, mineBlock, increaseTime } from "./shared/utilities"

describe("LPManager", function() {
  it("addLiquidity, removeLiquidity", async function() {
    const {dai, bnbPriceFeed, daiPriceFeed, btc, usdp, plp, bnb, btcPriceFeed} = await loadMockTokenFixtures()
    const {vault, lpManager, user1, user2, user0, provider} = await loadVaultPureFixtures()
    // reset balance
    for(const user of [user0, user1, user2]) {
      await dai.connect(user).burn(await dai.balanceOf(user.address))
      await btc.connect(user).burn(await btc.balanceOf(user.address))
      await bnb.connect(user).burn(await bnb.balanceOf(user.address))
    }

    await dai.mint(user0.address, expandDecimals(100, 18))
    await dai.connect(user0).approve(lpManager.address, expandDecimals(100, 18))
    const initialBalanceUser0 = await dai.balanceOf(user0.address)
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
    await lpManager.connect(user0).setCooldownDuration(24 * 60 * 60)

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    // @ts-ignore
    await vault.setConfigToken(...getDaiConfig(dai))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    //@ts-ignore
    await vault.setConfigToken(...getBtcConfig(btc))

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    // @ts-ignore
    await vault.setConfigToken(...getBnbConfig(bnb))

    await plp.setInPrivateTransferMode(true)
    await plp.setMinter(lpManager.address, true)

    await expect(lpManager.connect(user0).addLiquidity(
      dai.address,
      expandDecimals(100, 18),
      expandDecimals(101, 18),
      expandDecimals(101, 18)
    )).to.be.revertedWith("Vault: caller not in whitelist")

    await vault.setWhitelistCaller(lpManager.address, true)

    await expect(lpManager.connect(user0).addLiquidity(
      dai.address,
      expandDecimals(100, 18),
      expandDecimals(101, 18),
      expandDecimals(101, 18)
    )).to.be.revertedWith("LpManager: insufficient USDP output")

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400))
    expect(await dai.balanceOf(user0.address)).eq(initialBalanceUser0.toString())
    expect(await dai.balanceOf(vault.address)).eq(0, 'dai balance valt')
    expect(await usdp.balanceOf(lpManager.address)).eq(0)
    expect(await plp.balanceOf(user0.address)).eq(0)
    expect(await lpManager.lastAddedAt(user0.address)).eq(0)
    expect(await lpManager.getAumInUsdp(true)).eq(0)

    const tx0 = await lpManager.connect(user0).addLiquidity(
      dai.address,
      expandDecimals(100, 18),
      expandDecimals(99, 18),
      expandDecimals(99, 18)
    )
    // await reportGasUsed(provider, tx0, "addLiquidity gas used")

    let blockTime = await getBlockTime(provider,tx0.blockNumber)

    expect(await dai.balanceOf(user0.address)).eq(initialBalanceUser0.sub(expandDecimals(100, 18)).toString())
    expect(await dai.balanceOf(vault.address)).eq(expandDecimals(100, 18))
    expect(await usdp.balanceOf(lpManager.address)).eq("99700000000000000000") // 99.7
    expect(await plp.balanceOf(user0.address)).eq("99700000000000000000")
    expect(await plp.totalSupply()).eq("99700000000000000000")
    expect(await lpManager.lastAddedAt(user0.address)).eq(blockTime)
    expect(await lpManager.getAumInUsdp(true)).eq("99700000000000000000")
    expect(await lpManager.getAumInUsdp(false)).eq("99700000000000000000")

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))

    await lpManager.connect(user1).addLiquidity(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )
    blockTime = await getBlockTime(provider)

    expect(await usdp.balanceOf(lpManager.address)).eq("398800000000000000000") // 398.8
    expect(await plp.balanceOf(user0.address)).eq("99700000000000000000") // 99.7
    expect(await plp.balanceOf(user1.address)).eq("299100000000000000000") // 299.1
    expect(await plp.totalSupply()).eq("398800000000000000000")
    expect(await lpManager.lastAddedAt(user1.address)).eq(blockTime)
    expect(await lpManager.getAumInUsdp(true)).eq("498500000000000000000")
    expect(await lpManager.getAumInUsdp(false)).eq("398800000000000000000")

    await expect(plp.connect(user1).transfer(user2.address, expandDecimals(1, 18)))
      .to.be.revertedWith("BaseToken: msg.sender not whitelisted")

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500))

    expect(await lpManager.getAumInUsdp(true)).eq("598200000000000000000") // 598.2
    expect(await lpManager.getAumInUsdp(false)).eq("498500000000000000000") // 498.5

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))

    await btc.mint(user2.address, "1000000") // 0.01 BTC, $500
    await btc.connect(user2).approve(lpManager.address, expandDecimals(1, 18))

    await expect(lpManager.connect(user2).addLiquidity(
      btc.address,
      "1000000",
      expandDecimals(599, 18),
      expandDecimals(399, 18)
    )).to.be.revertedWith("LpManager: insufficient USDP output")

    console.log("127")

    await expect(lpManager.connect(user2).addLiquidity(
      btc.address,
      "1000000",
      expandDecimals(598, 18),
      expandDecimals(399, 18)
    )).to.be.revertedWith("LpManager: insufficient PLP output")

    console.log("137")
    await lpManager.connect(user2).addLiquidity(
      btc.address,
      "1000000",
      expandDecimals(598, 18),
      expandDecimals(398, 18)
    )
    console.log("143")

    blockTime = await getBlockTime(provider)

    expect(await usdp.balanceOf(lpManager.address)).eq("997000000000000000000") // 997
    expect(await plp.balanceOf(user0.address)).eq("99700000000000000000") // 99.7
    expect(await plp.balanceOf(user1.address)).eq("299100000000000000000") // 299.1
    expect(await plp.balanceOf(user2.address)).eq("398800000000000000000") // 398.8
    expect(await plp.totalSupply()).eq("797600000000000000000") // 797.6
    expect(await lpManager.lastAddedAt(user2.address)).eq(blockTime)
    expect(await lpManager.getAumInUsdp(true)).eq("1196400000000000000000") // 1196.4
    expect(await lpManager.getAumInUsdp(false)).eq("1096700000000000000000") // 1096.7
    console.log("162 remove liquidity")
    await expect(lpManager.connect(user0).removeLiquidity(
      dai.address,
      "99700000000000000000",
      expandDecimals(123, 18),
      user0.address
    )).to.be.revertedWith("LpManager: cooldown duration not yet passed")
    console.log("169 after remove liquidity")

    await increaseTime(24 * 60 * 60 + 1)
    await mineBlock()

    await expect(lpManager.connect(user0).removeLiquidity(
      dai.address,
      expandDecimals(73, 18),
      expandDecimals(100, 18),
      user0.address
    )).to.be.revertedWith("Vault: poolAmount exceeded")

    expect(await dai.balanceOf(user0.address)).eq(0)
    expect(await plp.balanceOf(user0.address)).eq("99700000000000000000") // 99.7

    await lpManager.connect(user0).removeLiquidity(
      dai.address,
      expandDecimals(72, 18),
      expandDecimals(98, 18),
      user0.address
    )

    expect(await dai.balanceOf(user0.address)).eq("98703000000000000000") // 98.703, 72 * 1096.7 / 797.6 => 99
    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await plp.balanceOf(user0.address)).eq("27700000000000000000") // 27.7

    await lpManager.connect(user0).removeLiquidity(
      bnb.address,
      "27700000000000000000", // 27.7, 27.7 * 1096.7 / 797.6 => 38.0875
      "75900000000000000", // 0.0759 BNB => 37.95 USD
      user0.address
    )

    expect(await dai.balanceOf(user0.address)).eq("98703000000000000000")
    expect(await bnb.balanceOf(user0.address)).eq("75946475000000000") // 0.075946475
    expect(await plp.balanceOf(user0.address)).eq(0)

    expect(await plp.totalSupply()).eq("697900000000000000000") // 697.9
    expect(await lpManager.getAumInUsdp(true)).eq("1059312500000000000000") // 1059.3125
    expect(await lpManager.getAumInUsdp(false)).eq("967230000000000000000") // 967.23

    expect(await bnb.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq("299100000000000000000")

    await lpManager.connect(user1).removeLiquidity(
      bnb.address,
      "299100000000000000000", // 299.1, 299.1 * 967.23 / 697.9 => 414.527142857
      "826500000000000000", // 0.8265 BNB => 413.25
      user1.address
    )

    expect(await bnb.balanceOf(user1.address)).eq("826567122857142856") // 0.826567122857142856
    expect(await plp.balanceOf(user1.address)).eq(0)

    expect(await plp.totalSupply()).eq("398800000000000000000") // 398.8
    expect(await lpManager.getAumInUsdp(true)).eq("644785357142857143000") // 644.785357142857143
    expect(await lpManager.getAumInUsdp(false)).eq("635608285714285714400") // 635.6082857142857144

    expect(await btc.balanceOf(user2.address)).eq(0)
    expect(await plp.balanceOf(user2.address)).eq("398800000000000000000") // 398.8

    expect(await vault.poolAmounts(dai.address)).eq("700000000000000000") // 0.7
    expect(await vault.poolAmounts(bnb.address)).eq("91770714285714286") // 0.091770714285714286
    expect(await vault.poolAmounts(btc.address)).eq("997000") // 0.00997

    await expect(lpManager.connect(user2).removeLiquidity(
      btc.address,
      expandDecimals(375, 18),
      "990000", // 0.0099
      user2.address
    )).to.be.revertedWith("Caller is not a vault")

    await usdp.addVault(lpManager.address)

    const tx1 = await lpManager.connect(user2).removeLiquidity(
      btc.address,
      expandDecimals(375, 18),
      "990000", // 0.0099
      user2.address
    )
    // await reportGasUsed(provider, tx1, "removeLiquidity gas used")

    expect(await btc.balanceOf(user2.address)).eq("993137")
    expect(await plp.balanceOf(user2.address)).eq("23800000000000000000") // 23.8
  })


})
