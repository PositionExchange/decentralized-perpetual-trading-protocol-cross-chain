import { expect } from "chai"
import { ethers } from "hardhat"
import { BonusDistributor, LpManager, MintableBaseToken, MockToken, PLP, POSI, PriceFeed, RewardDistributor, RewardRouter, RewardTracker, Timelock, USDP, Vault, VaultPriceFeed, Vester, WETH } from "../../typeChain"
import { EsPOSI } from "../../typeChain/contracts/token/posi/EsPOSI.sol"
import { getBnbConfig, getBtcConfig, getDaiConfig } from "../shared/config"
import { deployContractFixtures, loadMockTokenFixtures, loadVaultPureFixtures } from "../shared/fixtures"
import { deployContract, expandDecimals, increaseTime, mineBlock, newWallet, toChainlinkPrice } from "../shared/utilities"

describe("RewardRouter", function () {

  const vestingDuration = 365 * 24 * 60 * 60
  let timelock: Timelock
  let vault: Vault
  let lpManager: LpManager
  let plp: PLP
  let usdp: USDP
  let router
  let vaultPriceFeed: VaultPriceFeed
  let bnb: WETH
  let bnbPriceFeed: PriceFeed
  let btc: MockToken
  let btcPriceFeed: PriceFeed
  let eth: WETH
  let ethPriceFeed: PriceFeed
  let dai: MockToken
  let daiPriceFeed: PriceFeed
  let busd: MockToken
  let busdPriceFeed: PriceFeed
  let posi: POSI
  let esPosi: EsPOSI
  let bnPosi: MintableBaseToken
  let stakedPosiTracker: RewardTracker
  let stakedPosiDistributor: RewardDistributor
  let bonusPosiTracker: RewardTracker
  let bonusPosiDistributor: BonusDistributor
  let feePosiTracker: RewardTracker
  let feePosiDistributor: RewardDistributor
  let feePlpTracker: RewardTracker
  let feePlpDistributor: RewardDistributor
  let stakedPlpTracker: RewardTracker
  let stakedPlpDistributor: RewardDistributor
  let posiVester: Vester
  let plpVester: Vester
  let rewardRouter: RewardRouter
  // @ts-ignore
  let [wallet, user0, user1, user2, user3, user4, tokenManager] = [] as any
  const provider = ethers.provider

  beforeEach(async () => {
    const tokenFixtures = await loadMockTokenFixtures()
    const contractFixtures = await deployContractFixtures()
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
    // provider = contractFixtures.provider
    const users = await ethers.getSigners()
    wallet = users[0]
    user0 = users[1]
    user1 = users[2]
    user2 = users[3]
    user3 = users[4]
    user4 = users[5]
    tokenManager = users[5]

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await tokenFixtures.busdPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await tokenFixtures.usdtPriceFeed.setLatestAnswer(toChainlinkPrice(1))
    await tokenFixtures.wethPriceFeed.setLatestAnswer(toChainlinkPrice(1500))
    await tokenFixtures.btcPriceFeed.setLatestAnswer(toChainlinkPrice(20000))
    // @ts-ignore
    await vault.setConfigToken(...getDaiConfig(dai))

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000))
    // @ts-ignore
    await vault.setConfigToken(...getBtcConfig(btc))

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300))
    // @ts-ignore
    await vault.setConfigToken(...getBnbConfig(bnb))

    await vault.setFees(
      50, // _taxBasisPoints
      10, // _stableTaxBasisPoints
      30, // _mintBurnFeeBasisPoints
      30, // _swapFeeBasisPoints
      4, // _stableSwapFeeBasisPoints
      10, // _marginFeeBasisPoints
      0, // _minProfitTime
      false // _hasDynamicFees
    )

    await lpManager.setCooldownDuration(24*60*60)

    await plp.setInPrivateTransferMode(true)
    await plp.setMinter(lpManager.address, true)
    // await lpManager.setInPrivateMode(true)

    posi = await deployContract("POSI", []);
    esPosi = await deployContract("EsPOSI", []);
    bnPosi = await deployContract("MintableBaseToken", ["Bonus posi", "bnPOSI", 0]);

    // posi
    stakedPosiTracker = await deployContract("RewardTracker", ["Staked posi", "sPOSI"])
    stakedPosiDistributor = await deployContract("RewardDistributor", [esPosi.address, stakedPosiTracker.address])
    await stakedPosiTracker.initialize([posi.address, esPosi.address], stakedPosiDistributor.address)
    await stakedPosiDistributor.updateLastDistributionTime()

    bonusPosiTracker = await deployContract("RewardTracker", ["Staked + Bonus posi", "sbPOSI"])
    bonusPosiDistributor = await deployContract("BonusDistributor", [bnPosi.address, bonusPosiTracker.address])
    await bonusPosiTracker.initialize([stakedPosiTracker.address], bonusPosiDistributor.address)
    await bonusPosiDistributor.updateLastDistributionTime()

    feePosiTracker = await deployContract("RewardTracker", ["Staked + Bonus + Fee posi", "sbfPOSI"])
    feePosiDistributor = await deployContract("RewardDistributor", [eth.address, feePosiTracker.address])
    await feePosiTracker.initialize([bonusPosiTracker.address, bnPosi.address], feePosiDistributor.address)
    await feePosiDistributor.updateLastDistributionTime()

    // plp
    feePlpTracker = await deployContract("RewardTracker", ["Fee GLP", "fGLP"])
    feePlpTracker = feePlpTracker
    feePlpDistributor = await deployContract("RewardDistributor", [eth.address, feePlpTracker.address])
    await feePlpTracker.initialize([plp.address], feePlpDistributor.address)
    await feePlpDistributor.updateLastDistributionTime()

    stakedPlpTracker = await deployContract("RewardTracker", ["Fee + Staked GLP", "fsGLP"])
    stakedPlpDistributor = await deployContract("RewardDistributor", [esPosi.address, stakedPlpTracker.address])
    await stakedPlpTracker.initialize([feePlpTracker.address], stakedPlpDistributor.address)
    await stakedPlpDistributor.updateLastDistributionTime()

    posiVester = await deployContract("Vester", [
      "Vested posi", // _name
      "vPOSI", // _symbol
      vestingDuration, // _vestingDuration
      esPosi.address, // _esToken
      feePosiTracker.address, // _pairToken
      posi.address, // _claimableToken
      stakedPosiTracker.address, // _rewardTracker
    ])

    plpVester = await deployContract("Vester", [
      "Vested plp", // _name
      "vPlp", // _symbol
      vestingDuration, // _vestingDuration
      esPosi.address, // _esToken
      stakedPlpTracker.address, // _pairToken
      posi.address, // _claimableToken
      stakedPlpTracker.address, // _rewardTracker
    ])

    await stakedPosiTracker.setInPrivateTransferMode(true)
    await stakedPosiTracker.setInPrivateStakingMode(true)
    await bonusPosiTracker.setInPrivateTransferMode(true)
    await bonusPosiTracker.setInPrivateStakingMode(true)
    await bonusPosiTracker.setInPrivateClaimingMode(true)
    await feePosiTracker.setInPrivateTransferMode(true)
    await feePosiTracker.setInPrivateStakingMode(true)

    await feePlpTracker.setInPrivateTransferMode(true)
    await feePlpTracker.setInPrivateStakingMode(true)
    await stakedPlpTracker.setInPrivateTransferMode(true)
    await stakedPlpTracker.setInPrivateStakingMode(true)

    await esPosi.setInPrivateTransferMode(true)

    rewardRouter = await deployContract("RewardRouter", [
      bnb.address,
      posi.address,
      esPosi.address,
      bnPosi.address,
      plp.address,
    ])
    await rewardRouter.initialize(
      stakedPosiTracker.address,
      bonusPosiTracker.address,
      feePosiTracker.address,
      feePlpTracker.address,
      stakedPlpTracker.address,
      lpManager.address,
      posiVester.address,
      plpVester.address
    )

    timelock = await deployContract("Timelock", [
      wallet.address, // _admin
      10, // _buffer
      tokenManager.address, // _tokenManager
      tokenManager.address, // _mintReceiver
      lpManager.address, // _glpManager
      user0.address, // _rewardRouter
      expandDecimals(1000000, 18), // _maxTokenSupply
      10, // marginFeeBasisPoints
      100 // maxMarginFeeBasisPoints
    ])

    // allow bonusPosiTracker to stake stakedPosiTracker
    await stakedPosiTracker.setHandler(bonusPosiTracker.address, true)
    // allow bonusPosiTracker to stake feePosiTracker
    await bonusPosiTracker.setHandler(feePosiTracker.address, true)
    await bonusPosiDistributor.setBonusMultiplier(10000)
    // allow feePosiTracker to stake bnPosi
    await bnPosi.setHandler(feePosiTracker.address, true)

    // allow stakedPlpTracker to stake feePlpTracker
    await feePlpTracker.setHandler(stakedPlpTracker.address, true)
    // allow feePlpTracker to stake plp
    await plp.setHandler(feePlpTracker.address, true)

    // mint esPosi for distributors
    await esPosi.setMinter(wallet.address, true)
    await esPosi.mint(stakedPosiDistributor.address, expandDecimals(50000, 18))
    await stakedPosiDistributor.setTokensPerInterval("20667989410000000") // 0.02066798941 esPosi per second
    await esPosi.mint(stakedPlpDistributor.address, expandDecimals(50000, 18))
    await stakedPlpDistributor.setTokensPerInterval("20667989410000000") // 0.02066798941 esPosi per second

    // mint bnPosi for distributor
    await bnPosi.setMinter(wallet.address, true)
    await bnPosi.mint(bonusPosiDistributor.address, expandDecimals(1500, 18))

    await esPosi.setHandler(tokenManager.address, true)
    await posiVester.setHandler(wallet.address, true)

    await esPosi.setHandler(rewardRouter.address, true)
    await esPosi.setHandler(stakedPosiDistributor.address, true)
    await esPosi.setHandler(stakedPlpDistributor.address, true)
    await esPosi.setHandler(stakedPosiTracker.address, true)
    await esPosi.setHandler(stakedPlpTracker.address, true)
    await esPosi.setHandler(posiVester.address, true)
    await esPosi.setHandler(plpVester.address, true)

    await lpManager.setHandler(rewardRouter.address, true)
    await stakedPosiTracker.setHandler(rewardRouter.address, true)
    await bonusPosiTracker.setHandler(rewardRouter.address, true)
    await feePosiTracker.setHandler(rewardRouter.address, true)
    await feePlpTracker.setHandler(rewardRouter.address, true)
    await stakedPlpTracker.setHandler(rewardRouter.address, true)

    await esPosi.setHandler(rewardRouter.address, true)
    await bnPosi.setMinter(rewardRouter.address, true)
    await esPosi.setMinter(posiVester.address, true)
    await esPosi.setMinter(plpVester.address, true)

    await posiVester.setHandler(rewardRouter.address, true)
    await plpVester.setHandler(rewardRouter.address, true)

    await feePosiTracker.setHandler(posiVester.address, true)
    await stakedPlpTracker.setHandler(plpVester.address, true)

    await lpManager.transferOwnership(timelock.address)
    await stakedPosiTracker.setGov(timelock.address)
    await bonusPosiTracker.setGov(timelock.address)
    await feePosiTracker.setGov(timelock.address)
    await feePlpTracker.setGov(timelock.address)
    await stakedPlpTracker.setGov(timelock.address)
    await stakedPosiDistributor.setGov(timelock.address)
    await stakedPlpDistributor.setGov(timelock.address)
    await esPosi.setGov(timelock.address)
    await bnPosi.setGov(timelock.address)
    await posiVester.setGov(timelock.address)
    await plpVester.setGov(timelock.address)

    // [timelock, vault, lpManager, plp, usdp, router, vaultPriceFeed, bnb, bnbPriceFeed, btc, btcPriceFeed, eth, ethPriceFeed, dai, daiPriceFeed, busd, busdPriceFeed, posi, esPosi, bnPosi, stakedPosiTracker, stakedPosiDistributor, bonusPosiTracker, bonusPosiDistributor, feePosiTracker, feePosiDistributor, feePlpTracker, feePlpTracker, feePlpDistributor, stakedPlpTracker, stakedPlpDistributor, posiVester, plpVester, rewardRouter].forEach((element:any) => {
    //   expect(element).to.not.equal(undefined)
    // });
  })

  it("inits", async () => {
    expect(await rewardRouter.isInitialized()).eq(true)

    expect(await rewardRouter.weth()).eq(bnb.address)
    expect(await rewardRouter.posi()).eq(posi.address)
    expect(await rewardRouter.esPosi()).eq(esPosi.address)
    expect(await rewardRouter.bnPosi()).eq(bnPosi.address)

    expect(await rewardRouter.plp()).eq(plp.address)

    expect(await rewardRouter.stakedPosiTracker()).eq(stakedPosiTracker.address)
    expect(await rewardRouter.bonusPosiTracker()).eq(bonusPosiTracker.address)
    expect(await rewardRouter.feePosiTracker()).eq(feePosiTracker.address)

    expect(await rewardRouter.feePlpTracker()).eq(feePlpTracker.address)
    expect(await rewardRouter.stakedPlpTracker()).eq(stakedPlpTracker.address)

    expect(await rewardRouter.plpManager()).eq(lpManager.address)

    expect(await rewardRouter.posiVester()).eq(posiVester.address)
    expect(await rewardRouter.plpVester()).eq(plpVester.address)

    await expect(rewardRouter.initialize(
      stakedPosiTracker.address,
      bonusPosiTracker.address,
      feePosiTracker.address,
      feePlpTracker.address,
      stakedPlpTracker.address,
      lpManager.address,
      posiVester.address,
      plpVester.address
    )).to.be.revertedWith("Initializable: contract is already initialized")
  })

  it("stakePosiForAccount, stakePosi, stakeEsPosi, unstakePosi, unstakeEsPosi, claimEsPosi, claimFees, compound, batchCompoundForAccounts", async () => {
    await eth.mint(feePosiDistributor.address, expandDecimals(100, 18))
    await feePosiDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await posi.setMinter(wallet.address, true)
    await posi.mint(user0.address, expandDecimals(1500, 18))
    expect(await posi.balanceOf(user0.address)).eq(expandDecimals(1500, 18))

    await posi.connect(user0).approve(stakedPosiTracker.address, expandDecimals(1000, 18))
    console.log("301", await rewardRouter.gov(), user0.address)
    await expect(rewardRouter.connect(user0).stakePosiForAccount(user1.address, expandDecimals(1000, 18)))
      .to.be.revertedWith("Governable: forbidden")
    console.log("304")

    await rewardRouter.setGov(user0.address)
    await rewardRouter.connect(user0).stakePosiForAccount(user1.address, expandDecimals(800, 18))
    expect(await posi.balanceOf(user0.address)).eq(expandDecimals(700, 18))

    await posi.mint(user1.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(200, 18))
    await posi.connect(user1).approve(stakedPosiTracker.address, expandDecimals(200, 18))
    await rewardRouter.connect(user1).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)

    expect(await stakedPosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user0.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(1000, 18))

    expect(await bonusPosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await bonusPosiTracker.depositBalances(user0.address, stakedPosiTracker.address)).eq(0)
    expect(await bonusPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await bonusPosiTracker.depositBalances(user1.address, stakedPosiTracker.address)).eq(expandDecimals(1000, 18))

    expect(await feePosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user0.address, bonusPosiTracker.address)).eq(0)
    expect(await feePosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).eq(expandDecimals(1000, 18))

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    expect(await stakedPosiTracker.claimable(user0.address)).eq(0)
    expect(await stakedPosiTracker.claimable(user1.address)).gt(expandDecimals(1785, 18)) // 50000 / 28 => ~1785
    expect(await stakedPosiTracker.claimable(user1.address)).lt(expandDecimals(1786, 18))

    expect(await bonusPosiTracker.claimable(user0.address)).eq(0)
    expect(await bonusPosiTracker.claimable(user1.address)).gt("2730000000000000000") // 2.73, 1000 / 365 => ~2.74
    expect(await bonusPosiTracker.claimable(user1.address)).lt("2750000000000000000") // 2.75

    expect(await feePosiTracker.claimable(user0.address)).eq(0)
    expect(await feePosiTracker.claimable(user1.address)).gt("3560000000000000000") // 3.56, 100 / 28 => ~3.57
    expect(await feePosiTracker.claimable(user1.address)).lt("3580000000000000000") // 3.58

    await timelock.signalMint(esPosi.address, tokenManager.address, expandDecimals(500, 18))
    await increaseTime(20)
    await mineBlock()

    await timelock.processMint(esPosi.address, tokenManager.address, expandDecimals(500, 18))
    await esPosi.connect(tokenManager).transferFrom(tokenManager.address, user2.address, expandDecimals(500, 18))
    await rewardRouter.connect(user2).stakeEsPosi(expandDecimals(500, 18))

    expect(await stakedPosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user0.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(1000, 18))
    expect(await stakedPosiTracker.stakedAmounts(user2.address)).eq(expandDecimals(500, 18))
    expect(await stakedPosiTracker.depositBalances(user2.address, esPosi.address)).eq(expandDecimals(500, 18))

    expect(await bonusPosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await bonusPosiTracker.depositBalances(user0.address, stakedPosiTracker.address)).eq(0)
    expect(await bonusPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await bonusPosiTracker.depositBalances(user1.address, stakedPosiTracker.address)).eq(expandDecimals(1000, 18))
    expect(await bonusPosiTracker.stakedAmounts(user2.address)).eq(expandDecimals(500, 18))
    expect(await bonusPosiTracker.depositBalances(user2.address, stakedPosiTracker.address)).eq(expandDecimals(500, 18))

    expect(await feePosiTracker.stakedAmounts(user0.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user0.address, bonusPosiTracker.address)).eq(0)
    expect(await feePosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).eq(expandDecimals(1000, 18))
    expect(await feePosiTracker.stakedAmounts(user2.address)).eq(expandDecimals(500, 18))
    expect(await feePosiTracker.depositBalances(user2.address, bonusPosiTracker.address)).eq(expandDecimals(500, 18))

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    expect(await stakedPosiTracker.claimable(user0.address)).eq(0)
    expect(await stakedPosiTracker.claimable(user1.address)).gt(expandDecimals(1785 + 1190, 18))
    expect(await stakedPosiTracker.claimable(user1.address)).lt(expandDecimals(1786 + 1191, 18))
    expect(await stakedPosiTracker.claimable(user2.address)).gt(expandDecimals(595, 18))
    expect(await stakedPosiTracker.claimable(user2.address)).lt(expandDecimals(596, 18))

    expect(await bonusPosiTracker.claimable(user0.address)).eq(0)
    expect(await bonusPosiTracker.claimable(user1.address)).gt("5470000000000000000") // 5.47, 1000 / 365 * 2 => ~5.48
    expect(await bonusPosiTracker.claimable(user1.address)).lt("5490000000000000000")
    expect(await bonusPosiTracker.claimable(user2.address)).gt("1360000000000000000") // 1.36, 500 / 365 => ~1.37
    expect(await bonusPosiTracker.claimable(user2.address)).lt("1380000000000000000")

    expect(await feePosiTracker.claimable(user0.address)).eq(0)
    expect(await feePosiTracker.claimable(user1.address)).gt("5940000000000000000") // 5.94, 3.57 + 100 / 28 / 3 * 2 => ~5.95
    expect(await feePosiTracker.claimable(user1.address)).lt("5960000000000000000")
    expect(await feePosiTracker.claimable(user2.address)).gt("1180000000000000000") // 1.18, 100 / 28 / 3 => ~1.19
    expect(await feePosiTracker.claimable(user2.address)).lt("1200000000000000000")

    expect(await esPosi.balanceOf(user1.address)).eq(0)
    await rewardRouter.connect(user1).claimEsPosi()
    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(1785 + 1190, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(1786 + 1191, 18))

    expect(await eth.balanceOf(user1.address)).eq(0)
    await rewardRouter.connect(user1).claimFees()
    expect(await eth.balanceOf(user1.address)).gt("5940000000000000000")
    expect(await eth.balanceOf(user1.address)).lt("5960000000000000000")

    expect(await esPosi.balanceOf(user2.address)).eq(0)
    await rewardRouter.connect(user2).claimEsPosi()
    expect(await esPosi.balanceOf(user2.address)).gt(expandDecimals(595, 18))
    expect(await esPosi.balanceOf(user2.address)).lt(expandDecimals(596, 18))

    expect(await eth.balanceOf(user2.address)).eq(0)
    await rewardRouter.connect(user2).claimFees()
    expect(await eth.balanceOf(user2.address)).gt("1180000000000000000")
    expect(await eth.balanceOf(user2.address)).lt("1200000000000000000")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    const tx0 = await rewardRouter.connect(user1).compound()
    // await reportGasUsed(provider, tx0, "compound gas used")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    const tx1 = await rewardRouter.connect(user0).batchCompoundForAccounts([user1.address, user2.address])
    // await reportGasUsed(provider, tx1, "batchCompoundForAccounts gas used")

    expect(await stakedPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3643, 18))
    expect(await stakedPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3645, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(1000, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(2643, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(2645, 18))

    expect(await bonusPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3643, 18))
    expect(await bonusPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3645, 18))

    expect(await feePosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3657, 18))
    expect(await feePosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3659, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).gt(expandDecimals(3643, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).lt(expandDecimals(3645, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("14100000000000000000") // 14.1
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("14300000000000000000") // 14.3

    expect(await posi.balanceOf(user1.address)).eq(0)
    await rewardRouter.connect(user1).unstakePosi(expandDecimals(300, 18))
    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(300, 18))

    expect(await stakedPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3343, 18))
    expect(await stakedPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3345, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(700, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(2643, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(2645, 18))

    expect(await bonusPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3343, 18))
    expect(await bonusPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3345, 18))

    expect(await feePosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(3357, 18))
    expect(await feePosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(3359, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).gt(expandDecimals(3343, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).lt(expandDecimals(3345, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("13000000000000000000") // 13
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("13100000000000000000") // 13.1

    const esPosiBalance1 = await esPosi.balanceOf(user1.address)
    const esPosiUnstakeBalance1 = await stakedPosiTracker.depositBalances(user1.address, esPosi.address)
    await rewardRouter.connect(user1).unstakeEsPosi(esPosiUnstakeBalance1)
    expect(await esPosi.balanceOf(user1.address)).eq(esPosiBalance1.add(esPosiUnstakeBalance1))

    expect(await stakedPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(700, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(700, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).eq(0)

    expect(await bonusPosiTracker.stakedAmounts(user1.address)).eq(expandDecimals(700, 18))

    expect(await feePosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(702, 18))
    expect(await feePosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(703, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).eq(expandDecimals(700, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("2720000000000000000") // 2.72
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("2740000000000000000") // 2.74

    await expect(rewardRouter.connect(user1).unstakeEsPosi(expandDecimals(1, 18)))
      .to.be.revertedWith("RewardTracker: _amount exceeds depositBalance")
  })

  it("mintAndStakePlp, unstakeAndRedeemPlp, compound, batchCompoundForAccounts", async () => {
    await eth.mint(feePlpDistributor.address, expandDecimals(100, 18))
    await feePlpDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))
    console.log("490")
    const tx0 = await rewardRouter.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )
    console.log("497")
    // await reportGasUsed(provider, tx0, "mintAndStakePlp gas used")

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))

    await bnb.mint(user1.address, expandDecimals(2, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(2, 18))
    console.log("520")

    await rewardRouter.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(2, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )

    await increaseTime(24 * 60 * 60 + 1)
    await mineBlock()

    expect(await feePlpTracker.claimable(user1.address)).gt("3560000000000000000") // 3.56, 100 / 28 => ~3.57
    expect(await feePlpTracker.claimable(user1.address)).lt("3580000000000000000") // 3.58

    expect(await stakedPlpTracker.claimable(user1.address)).gt(expandDecimals(1785, 18)) // 50000 / 28 => ~1785
    expect(await stakedPlpTracker.claimable(user1.address)).lt(expandDecimals(1786, 18))

    await bnb.mint(user2.address, expandDecimals(1, 18))
    await bnb.connect(user2).approve(lpManager.address, expandDecimals(1, 18))
    console.log("538")
    await rewardRouter.connect(user2).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )
    console.log("546")

    await expect(rewardRouter.connect(user2).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(299, 18),
      "990000000000000000", // 0.99
      user2.address
    )).to.be.revertedWith("LpManager: cooldown duration not yet passed")

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq("897300000000000000000") // 897.3
    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq("897300000000000000000")
    expect(await bnb.balanceOf(user1.address)).eq(0)

    const tx1 = await rewardRouter.connect(user1).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(299, 18),
      "990000000000000000", // 0.99
      user1.address
    )
    // await reportGasUsed(provider, tx1, "unstakeAndRedeemPlp gas used")

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq("598300000000000000000") // 598.3
    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq("598300000000000000000")
    expect(await bnb.balanceOf(user1.address)).eq("993676666666666666") // ~0.99

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    expect(await feePlpTracker.claimable(user1.address)).gt("5940000000000000000") // 5.94, 3.57 + 100 / 28 / 3 * 2 => ~5.95
    expect(await feePlpTracker.claimable(user1.address)).lt("5960000000000000000")
    expect(await feePlpTracker.claimable(user2.address)).gt("1180000000000000000") // 1.18, 100 / 28 / 3 => ~1.19
    expect(await feePlpTracker.claimable(user2.address)).lt("1200000000000000000")

    expect(await stakedPlpTracker.claimable(user1.address)).gt(expandDecimals(1785 + 1190, 18))
    expect(await stakedPlpTracker.claimable(user1.address)).lt(expandDecimals(1786 + 1191, 18))
    expect(await stakedPlpTracker.claimable(user2.address)).gt(expandDecimals(595, 18))
    expect(await stakedPlpTracker.claimable(user2.address)).lt(expandDecimals(596, 18))

    expect(await esPosi.balanceOf(user1.address)).eq(0)
    await rewardRouter.connect(user1).claimEsPosi()
    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(1785 + 1190, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(1786 + 1191, 18))

    expect(await eth.balanceOf(user1.address)).eq(0)
    await rewardRouter.connect(user1).claimFees()
    expect(await eth.balanceOf(user1.address)).gt("5940000000000000000")
    expect(await eth.balanceOf(user1.address)).lt("5960000000000000000")

    expect(await esPosi.balanceOf(user2.address)).eq(0)
    await rewardRouter.connect(user2).claimEsPosi()
    expect(await esPosi.balanceOf(user2.address)).gt(expandDecimals(595, 18))
    expect(await esPosi.balanceOf(user2.address)).lt(expandDecimals(596, 18))

    expect(await eth.balanceOf(user2.address)).eq(0)
    await rewardRouter.connect(user2).claimFees()
    expect(await eth.balanceOf(user2.address)).gt("1180000000000000000")
    expect(await eth.balanceOf(user2.address)).lt("1200000000000000000")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    const tx2 = await rewardRouter.connect(user1).compound()
    // await reportGasUsed(provider, tx2, "compound gas used")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    const tx3 = await rewardRouter.batchCompoundForAccounts([user1.address, user2.address])
    // await reportGasUsed(provider, tx1, "batchCompoundForAccounts gas used")

    expect(await stakedPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(4165, 18))
    expect(await stakedPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(4167, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(4165, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(4167, 18))

    expect(await bonusPosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(4165, 18))
    expect(await bonusPosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(4167, 18))

    expect(await feePosiTracker.stakedAmounts(user1.address)).gt(expandDecimals(4179, 18))
    expect(await feePosiTracker.stakedAmounts(user1.address)).lt(expandDecimals(4180, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).gt(expandDecimals(4165, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bonusPosiTracker.address)).lt(expandDecimals(4167, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("12900000000000000000") // 12.9
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("13100000000000000000") // 13.1

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq("598300000000000000000") // 598.3
    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq("598300000000000000000")
    expect(await bnb.balanceOf(user1.address)).eq("993676666666666666") // ~0.99
  })

  it("mintAndStakePlpETH, unstakeAndRedeemPlpETH", async () => {
    const receiver0 = newWallet()
    await expect(rewardRouter.connect(user0).mintAndStakePlpETH(expandDecimals(300, 18), expandDecimals(300, 18), { value: 0 }))
      .to.be.revertedWith("RewardRouter: invalid msg.value")
      console.log("RewardRouter.test.ts:644", eth.address);

    await expect(rewardRouter.connect(user0).mintAndStakePlpETH(expandDecimals(300, 18), expandDecimals(300, 18), { value: expandDecimals(1, 18) }))
      .to.be.revertedWith("LpManager: insufficient _usdp output")

    await expect(rewardRouter.connect(user0).mintAndStakePlpETH(expandDecimals(299, 18), expandDecimals(300, 18), { value: expandDecimals(1, 18) }))
      .to.be.revertedWith("LpManager: insufficient PLP output")

    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await bnb.balanceOf(vault.address)).eq(0)
    expect(await bnb.totalSupply()).eq(0)
    expect(await ethers.provider.getBalance(bnb.address)).eq(0)
    expect(await stakedPlpTracker.balanceOf(user0.address)).eq(0)

    await rewardRouter.connect(user0).mintAndStakePlpETH(expandDecimals(299, 18), expandDecimals(299, 18), { value: expandDecimals(1, 18) })

    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await bnb.balanceOf(vault.address)).eq(expandDecimals(1, 18))
    expect(await provider.getBalance(bnb.address)).eq(expandDecimals(1, 18))
    // expect(await bnb.totalSupply()).eq(expandDecimals(1, 18))
    expect(await stakedPlpTracker.balanceOf(user0.address)).eq("299100000000000000000") // 299.1

    await expect(rewardRouter.connect(user0).unstakeAndRedeemPlpETH(expandDecimals(300, 18), expandDecimals(1, 18), receiver0.address))
      .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount")

    await expect(rewardRouter.connect(user0).unstakeAndRedeemPlpETH("299100000000000000000", expandDecimals(1, 18), receiver0.address))
      .to.be.revertedWith("LpManager: cooldown duration not yet passed")

    await increaseTime(24 * 60 * 60 + 10)

    await expect(rewardRouter.connect(user0).unstakeAndRedeemPlpETH("299100000000000000000", expandDecimals(1, 18), receiver0.address))
      .to.be.revertedWith("LpManager: insufficient output")

    await rewardRouter.connect(user0).unstakeAndRedeemPlpETH("299100000000000000000", "990000000000000000", receiver0.address)
    expect(await provider.getBalance(receiver0.address)).eq("994009000000000000") // 0.994009
    expect(await bnb.balanceOf(vault.address)).eq("5991000000000000") // 0.005991
    expect(await provider.getBalance(bnb.address)).eq("5991000000000000")
    // expect(await bnb.totalSupply()).eq("5991000000000000")
  })

  it("posi: signalTransfer, acceptTransfer", async () =>{
    await posi.setMinter(wallet.address, true)
    await posi.mint(user1.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(200, 18))
    await posi.connect(user1).approve(stakedPosiTracker.address, expandDecimals(200, 18))
    await rewardRouter.connect(user1).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)

    await posi.mint(user2.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user2.address)).eq(expandDecimals(200, 18))
    await posi.connect(user2).approve(stakedPosiTracker.address, expandDecimals(400, 18))
    await rewardRouter.connect(user2).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user2.address)).eq(0)

    await rewardRouter.connect(user2).signalTransfer(user1.address)

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    await rewardRouter.connect(user2).signalTransfer(user1.address)
    await rewardRouter.connect(user1).claim()

    await expect(rewardRouter.connect(user2).signalTransfer(user1.address))
      .to.be.revertedWith("RewardRouter: stakedPosiTracker.averageStakedAmounts > 0")

    await rewardRouter.connect(user2).signalTransfer(user3.address)

    await expect(rewardRouter.connect(user3).acceptTransfer(user1.address))
      .to.be.revertedWith("RewardRouter: transfer not signalled")

    await posiVester.setBonusRewards(user2.address, expandDecimals(100, 18))

    expect(await stakedPosiTracker.depositBalances(user2.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user2.address, esPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user2.address, bnPosi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).eq(0)
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(0)
    expect(await posiVester.transferredCumulativeRewards(user3.address)).eq(0)
    expect(await posiVester.bonusRewards(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.bonusRewards(user3.address)).eq(0)
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).eq(0)
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).eq(0)
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(892, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(892, 18))).eq(0)

    await rewardRouter.connect(user3).acceptTransfer(user2.address)

    expect(await stakedPosiTracker.depositBalances(user2.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user2.address, esPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user2.address, bnPosi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).gt(expandDecimals(892, 18))
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).lt(expandDecimals(893, 18))
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).gt("547000000000000000") // 0.547
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).lt("549000000000000000") // 0.548
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).gt(expandDecimals(892, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).lt(expandDecimals(893, 18))
    expect(await posiVester.bonusRewards(user2.address)).eq(0)
    expect(await posiVester.bonusRewards(user3.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(992, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(994, 18))
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(992, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).gt(expandDecimals(199, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).lt(expandDecimals(200, 18))

    await posi.connect(user3).approve(stakedPosiTracker.address, expandDecimals(400, 18))
    await rewardRouter.connect(user3).signalTransfer(user4.address)
    await rewardRouter.connect(user4).acceptTransfer(user3.address)

    expect(await stakedPosiTracker.depositBalances(user3.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user4.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user4.address, esPosi.address)).gt(expandDecimals(892, 18))
    expect(await stakedPosiTracker.depositBalances(user4.address, esPosi.address)).lt(expandDecimals(894, 18))
    expect(await feePosiTracker.depositBalances(user4.address, bnPosi.address)).gt("547000000000000000") // 0.547
    expect(await feePosiTracker.depositBalances(user4.address, bnPosi.address)).lt("549000000000000000") // 0.548
    expect(await posiVester.transferredAverageStakedAmounts(user4.address)).gt(expandDecimals(200, 18))
    expect(await posiVester.transferredAverageStakedAmounts(user4.address)).lt(expandDecimals(201, 18))
    expect(await posiVester.transferredCumulativeRewards(user4.address)).gt(expandDecimals(892, 18))
    expect(await posiVester.transferredCumulativeRewards(user4.address)).lt(expandDecimals(894, 18))
    expect(await posiVester.bonusRewards(user3.address)).eq(0)
    expect(await posiVester.bonusRewards(user4.address)).eq(expandDecimals(100, 18))
    expect(await stakedPosiTracker.averageStakedAmounts(user3.address)).gt(expandDecimals(1092, 18))
    expect(await stakedPosiTracker.averageStakedAmounts(user3.address)).lt(expandDecimals(1094, 18))
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(0)
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).gt(expandDecimals(1092, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).lt(expandDecimals(1094, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user4.address)).gt(expandDecimals(200, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user4.address)).lt(expandDecimals(201, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user4.address)).gt(expandDecimals(992, 18))
    expect(await posiVester.getMaxVestableAmount(user4.address)).lt(expandDecimals(994, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).eq(0)
    expect(await posiVester.getPairAmount(user4.address, expandDecimals(992, 18))).gt(expandDecimals(199, 18))
    expect(await posiVester.getPairAmount(user4.address, expandDecimals(992, 18))).lt(expandDecimals(200, 18))

    await expect(rewardRouter.connect(user4).acceptTransfer(user3.address))
      .to.be.revertedWith("RewardRouter: transfer not signalled")
  })

  it("posi, plp: signalTransfer, acceptTransfer", async () =>{
    await posi.setMinter(wallet.address, true)
    await posi.mint(posiVester.address, expandDecimals(10000, 18))
    await posi.mint(plpVester.address, expandDecimals(10000, 18))
    await eth.mint(feePlpDistributor.address, expandDecimals(100, 18))
    await feePlpDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))
    await rewardRouter.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )

    await bnb.mint(user2.address, expandDecimals(1, 18))
    await bnb.connect(user2).approve(lpManager.address, expandDecimals(1, 18))
    await rewardRouter.connect(user2).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )

    await posi.mint(user1.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(200, 18))
    await posi.connect(user1).approve(stakedPosiTracker.address, expandDecimals(200, 18))
    await rewardRouter.connect(user1).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)

    await posi.mint(user2.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user2.address)).eq(expandDecimals(200, 18))
    await posi.connect(user2).approve(stakedPosiTracker.address, expandDecimals(400, 18))
    await rewardRouter.connect(user2).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user2.address)).eq(0)

    await rewardRouter.connect(user2).signalTransfer(user1.address)

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    await rewardRouter.connect(user2).signalTransfer(user1.address)
    await rewardRouter.connect(user1).compound()

    await expect(rewardRouter.connect(user2).signalTransfer(user1.address))
      .to.be.revertedWith("RewardRouter: stakedPosiTracker.averageStakedAmounts > 0")

    await rewardRouter.connect(user2).signalTransfer(user3.address)

    await expect(rewardRouter.connect(user3).acceptTransfer(user1.address))
      .to.be.revertedWith("RewardRouter: transfer not signalled")

    await posiVester.setBonusRewards(user2.address, expandDecimals(100, 18))

    expect(await stakedPosiTracker.depositBalances(user2.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user2.address, esPosi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).eq(0)

    expect(await feePosiTracker.depositBalances(user2.address, bnPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).eq(0)

    expect(await feePlpTracker.depositBalances(user2.address, plp.address)).eq("299100000000000000000") // 299.1
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(0)

    expect(await stakedPlpTracker.depositBalances(user2.address, feePlpTracker.address)).eq("299100000000000000000") // 299.1
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(0)

    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(0)
    expect(await posiVester.transferredCumulativeRewards(user3.address)).eq(0)
    expect(await posiVester.bonusRewards(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.bonusRewards(user3.address)).eq(0)
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).eq(0)
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).eq(0)
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(892, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(892, 18))).eq(0)

    await rewardRouter.connect(user3).acceptTransfer(user2.address)

    expect(await stakedPosiTracker.depositBalances(user2.address, posi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user2.address, esPosi.address)).eq(0)
    expect(await stakedPosiTracker.depositBalances(user3.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).gt(expandDecimals(1785, 18))
    expect(await stakedPosiTracker.depositBalances(user3.address, esPosi.address)).lt(expandDecimals(1786, 18))

    expect(await feePosiTracker.depositBalances(user2.address, bnPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).gt("547000000000000000") // 0.547
    expect(await feePosiTracker.depositBalances(user3.address, bnPosi.address)).lt("549000000000000000") // 0.548

    expect(await feePlpTracker.depositBalances(user2.address, plp.address)).eq(0)
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq("299100000000000000000") // 299.1

    expect(await stakedPlpTracker.depositBalances(user2.address, feePlpTracker.address)).eq(0)
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq("299100000000000000000") // 299.1

    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).gt(expandDecimals(892, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).lt(expandDecimals(893, 18))
    expect(await posiVester.bonusRewards(user2.address)).eq(0)
    expect(await posiVester.bonusRewards(user3.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(992, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(993, 18))
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(992, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).gt(expandDecimals(199, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).lt(expandDecimals(200, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(892, 18))).gt(expandDecimals(199, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(892, 18))).lt(expandDecimals(200, 18))

    await rewardRouter.connect(user1).compound()

    await expect(rewardRouter.connect(user3).acceptTransfer(user1.address))
      .to.be.revertedWith("RewardRouter: transfer not signalled")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    await rewardRouter.connect(user1).claim()
    await rewardRouter.connect(user2).claim()
    await rewardRouter.connect(user3).claim()

    expect(await posiVester.getCombinedAverageStakedAmount(user1.address)).gt(expandDecimals(1092, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user1.address)).lt(expandDecimals(1094, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).gt(expandDecimals(1092, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).lt(expandDecimals(1094, 18))

    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(1885, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(1887, 18))
    expect(await posiVester.getMaxVestableAmount(user1.address)).gt(expandDecimals(1785, 18))
    expect(await posiVester.getMaxVestableAmount(user1.address)).lt(expandDecimals(1787, 18))

    expect(await posiVester.getPairAmount(user2.address, expandDecimals(992, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(1885, 18))).gt(expandDecimals(1092, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(1885, 18))).lt(expandDecimals(1094, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(1785, 18))).gt(expandDecimals(1092, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(1785, 18))).lt(expandDecimals(1094, 18))

    await rewardRouter.connect(user1).compound()
    await rewardRouter.connect(user3).compound()

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(1992, 18))
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(1993, 18))

    await posiVester.connect(user1).deposit(expandDecimals(1785, 18))

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(1991 - 1092, 18)) // 899
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(1993 - 1092, 18)) // 901

    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt(expandDecimals(4, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt(expandDecimals(6, 18))

    await rewardRouter.connect(user1).unstakePosi(expandDecimals(200, 18))
    await expect(rewardRouter.connect(user1).unstakeEsPosi(expandDecimals(699, 18)))
      .to.be.revertedWith("RewardTracker: burn amount exceeds balance")

    await rewardRouter.connect(user1).unstakeEsPosi(expandDecimals(599, 18))

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(97, 18))
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(99, 18))

    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(599, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(601, 18))

    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(200, 18))

    await posiVester.connect(user1).withdraw()

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(1190, 18)) // 1190 - 98 => 1092
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(1191, 18))

    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(2378, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(2380, 18))

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(204, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(206, 18))

    expect(await plpVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(1785, 18))
    expect(await plpVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(1787, 18))

    expect(await plpVester.getPairAmount(user3.address, expandDecimals(1785, 18))).gt(expandDecimals(298, 18))
    expect(await plpVester.getPairAmount(user3.address, expandDecimals(1785, 18))).lt(expandDecimals(300, 18))

    expect(await stakedPlpTracker.balanceOf(user3.address)).eq("299100000000000000000")

    expect(await esPosi.balanceOf(user3.address)).gt(expandDecimals(1785, 18))
    expect(await esPosi.balanceOf(user3.address)).lt(expandDecimals(1787, 18))

    expect(await posi.balanceOf(user3.address)).eq(0)

    await plpVester.connect(user3).deposit(expandDecimals(1785, 18))

    expect(await stakedPlpTracker.balanceOf(user3.address)).gt(0)
    expect(await stakedPlpTracker.balanceOf(user3.address)).lt(expandDecimals(1, 18))

    expect(await esPosi.balanceOf(user3.address)).gt(0)
    expect(await esPosi.balanceOf(user3.address)).lt(expandDecimals(1, 18))

    expect(await posi.balanceOf(user3.address)).eq(0)

    await expect(rewardRouter.connect(user3).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(1, 18),
      0,
      user3.address
    )).to.be.revertedWith("RewardTracker: burn amount exceeds balance")

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    await plpVester.connect(user3).withdraw()

    expect(await stakedPlpTracker.balanceOf(user3.address)).eq("299100000000000000000")

    expect(await esPosi.balanceOf(user3.address)).gt(expandDecimals(1785 - 5, 18))
    expect(await esPosi.balanceOf(user3.address)).lt(expandDecimals(1787 - 5, 18))

    expect(await posi.balanceOf(user3.address)).gt(expandDecimals(4, 18))
    expect(await posi.balanceOf(user3.address)).lt(expandDecimals(6, 18))

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(1190, 18))
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(1191, 18))

    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(2379, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(2381, 18))

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(204, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(206, 18))

    await posiVester.connect(user1).deposit(expandDecimals(365 * 2, 18))

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(743, 18)) // 1190 - 743 => 447
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(754, 18))

    expect(await posiVester.claimable(user1.address)).eq(0)

    await increaseTime(48 * 60 * 60)
    await mineBlock()

    expect(await posiVester.claimable(user1.address)).gt("3900000000000000000") // 3.9
    expect(await posiVester.claimable(user1.address)).lt("4100000000000000000") // 4.1

    await posiVester.connect(user1).deposit(expandDecimals(365, 18))

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(522, 18)) // 743 - 522 => 221
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(524, 18))

    await increaseTime(48 * 60 * 60)
    await mineBlock()

    expect(await posiVester.claimable(user1.address)).gt("9900000000000000000") // 9.9
    expect(await posiVester.claimable(user1.address)).lt("10100000000000000000") // 10.1

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(204, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(206, 18))

    await posiVester.connect(user1).claim()

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(214, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(216, 18))

    await posiVester.connect(user1).deposit(expandDecimals(365, 18))
    expect(await posiVester.balanceOf(user1.address)).gt(expandDecimals(1449, 18)) // 365 * 4 => 1460, 1460 - 10 => 1450
    expect(await posiVester.balanceOf(user1.address)).lt(expandDecimals(1451, 18))
    expect(await posiVester.getVestedAmount(user1.address)).eq(expandDecimals(1460, 18))

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(303, 18)) // 522 - 303 => 219
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(304, 18))

    await increaseTime(48 * 60 * 60)
    await mineBlock()

    expect(await posiVester.claimable(user1.address)).gt("7900000000000000000") // 7.9
    expect(await posiVester.claimable(user1.address)).lt("8100000000000000000") // 8.1

    await posiVester.connect(user1).withdraw()

    expect(await feePosiTracker.balanceOf(user1.address)).gt(expandDecimals(1190, 18))
    expect(await feePosiTracker.balanceOf(user1.address)).lt(expandDecimals(1191, 18))

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(222, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(224, 18))

    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(2360, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(2362, 18))

    await posiVester.connect(user1).deposit(expandDecimals(365, 18))

    await increaseTime(500 * 24 * 60 * 60)
    await mineBlock()

    expect(await posiVester.claimable(user1.address)).eq(expandDecimals(365, 18))

    await posiVester.connect(user1).withdraw()

    expect(await posi.balanceOf(user1.address)).gt(expandDecimals(222 + 365, 18))
    expect(await posi.balanceOf(user1.address)).lt(expandDecimals(224 + 365, 18))

    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(2360 - 365, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(2362 - 365, 18))

    expect(await posiVester.transferredAverageStakedAmounts(user2.address)).eq(0)
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.cumulativeRewards(user2.address)).gt(expandDecimals(892, 18))
    expect(await stakedPosiTracker.cumulativeRewards(user2.address)).lt(expandDecimals(893, 18))
    expect(await stakedPosiTracker.cumulativeRewards(user3.address)).gt(expandDecimals(892, 18))
    expect(await stakedPosiTracker.cumulativeRewards(user3.address)).lt(expandDecimals(893, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).gt(expandDecimals(892, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).lt(expandDecimals(893, 18))
    expect(await posiVester.bonusRewards(user2.address)).eq(0)
    expect(await posiVester.bonusRewards(user3.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).eq(expandDecimals(200, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).gt(expandDecimals(1092, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).lt(expandDecimals(1093, 18))
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(0)
    expect(await posiVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(1884, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(1886, 18))
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(992, 18))).eq(0)
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).gt(expandDecimals(574, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(992, 18))).lt(expandDecimals(575, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(892, 18))).gt(expandDecimals(545, 18))
    expect(await posiVester.getPairAmount(user1.address, expandDecimals(892, 18))).lt(expandDecimals(546, 18))

    const esPosiBatchSender = await deployContract("EsPosiBatchSender", [esPosi.address])

    await timelock.signalSetHandler(esPosi.address, esPosiBatchSender.address, true)
    await timelock.signalSetHandler(posiVester.address, esPosiBatchSender.address, true)
    await timelock.signalSetHandler(plpVester.address, esPosiBatchSender.address, true)
    await timelock.signalMint(esPosi.address, wallet.address, expandDecimals(1000, 18))

    await increaseTime(20)
    await mineBlock()

    await timelock.setHandler(esPosi.address, esPosiBatchSender.address, true)
    await timelock.setHandler(posiVester.address, esPosiBatchSender.address, true)
    await timelock.setHandler(plpVester.address, esPosiBatchSender.address, true)
    await timelock.processMint(esPosi.address, wallet.address, expandDecimals(1000, 18))

    await esPosiBatchSender.connect(wallet).send(
      posiVester.address,
      4,
      [user2.address, user3.address],
      [expandDecimals(100, 18), expandDecimals(200, 18)]
    )

    expect(await posiVester.transferredAverageStakedAmounts(user2.address)).gt(expandDecimals(37648, 18))
    expect(await posiVester.transferredAverageStakedAmounts(user2.address)).lt(expandDecimals(37649, 18))
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).gt(expandDecimals(12810, 18))
    expect(await posiVester.transferredAverageStakedAmounts(user3.address)).lt(expandDecimals(12811, 18))
    expect(await posiVester.transferredCumulativeRewards(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).gt(expandDecimals(892 + 200, 18))
    expect(await posiVester.transferredCumulativeRewards(user3.address)).lt(expandDecimals(893 + 200, 18))
    expect(await posiVester.bonusRewards(user2.address)).eq(0)
    expect(await posiVester.bonusRewards(user3.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).gt(expandDecimals(3971, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user2.address)).lt(expandDecimals(3972, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).gt(expandDecimals(7943, 18))
    expect(await posiVester.getCombinedAverageStakedAmount(user3.address)).lt(expandDecimals(7944, 18))
    expect(await posiVester.getMaxVestableAmount(user2.address)).eq(expandDecimals(100, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).gt(expandDecimals(1884 + 200, 18))
    expect(await posiVester.getMaxVestableAmount(user3.address)).lt(expandDecimals(1886 + 200, 18))
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(100, 18))).gt(expandDecimals(3971, 18))
    expect(await posiVester.getPairAmount(user2.address, expandDecimals(100, 18))).lt(expandDecimals(3972, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(1884 + 200, 18))).gt(expandDecimals(7936, 18))
    expect(await posiVester.getPairAmount(user3.address, expandDecimals(1884 + 200, 18))).lt(expandDecimals(7937, 18))

    expect(await plpVester.transferredAverageStakedAmounts(user4.address)).eq(0)
    expect(await plpVester.transferredCumulativeRewards(user4.address)).eq(0)
    expect(await plpVester.bonusRewards(user4.address)).eq(0)
    expect(await plpVester.getCombinedAverageStakedAmount(user4.address)).eq(0)
    expect(await plpVester.getMaxVestableAmount(user4.address)).eq(0)
    expect(await plpVester.getPairAmount(user4.address, expandDecimals(10, 18))).eq(0)

    await esPosiBatchSender.connect(wallet).send(
      plpVester.address,
      320,
      [user4.address],
      [expandDecimals(10, 18)]
    )

    expect(await plpVester.transferredAverageStakedAmounts(user4.address)).eq(expandDecimals(3200, 18))
    expect(await plpVester.transferredCumulativeRewards(user4.address)).eq(expandDecimals(10, 18))
    expect(await plpVester.bonusRewards(user4.address)).eq(0)
    expect(await plpVester.getCombinedAverageStakedAmount(user4.address)).eq(expandDecimals(3200, 18))
    expect(await plpVester.getMaxVestableAmount(user4.address)).eq(expandDecimals(10, 18))
    expect(await plpVester.getPairAmount(user4.address, expandDecimals(10, 18))).eq(expandDecimals(3200, 18))

    await esPosiBatchSender.connect(wallet).send(
      plpVester.address,
      320,
      [user4.address],
      [expandDecimals(10, 18)]
    )

    expect(await plpVester.transferredAverageStakedAmounts(user4.address)).eq(expandDecimals(6400, 18))
    expect(await plpVester.transferredCumulativeRewards(user4.address)).eq(expandDecimals(20, 18))
    expect(await plpVester.bonusRewards(user4.address)).eq(0)
    expect(await plpVester.getCombinedAverageStakedAmount(user4.address)).eq(expandDecimals(6400, 18))
    expect(await plpVester.getMaxVestableAmount(user4.address)).eq(expandDecimals(20, 18))
    expect(await plpVester.getPairAmount(user4.address, expandDecimals(10, 18))).eq(expandDecimals(3200, 18))
  })

  it("handleRewards", async () => {
    const timelockV2 = wallet

    // use new rewardRouter, use eth for weth
    const rewardRouterV2 = await deployContract("RewardRouter", [
      eth.address,
      posi.address,
      esPosi.address,
      bnPosi.address,
      plp.address,
  ]) as unknown as RewardRouter
  await rewardRouterV2.initialize(
      stakedPosiTracker.address,
      bonusPosiTracker.address,
      feePosiTracker.address,
      feePlpTracker.address,
      stakedPlpTracker.address,
      lpManager.address,
      posiVester.address,
      plpVester.address
    )
    console.log("RewardRouter.test.ts:1229", "initialized");
    

    await timelock.signalSetGov(lpManager.address, timelockV2.address)
    await timelock.signalSetGov(stakedPosiTracker.address, timelockV2.address)
    await timelock.signalSetGov(bonusPosiTracker.address, timelockV2.address)
    await timelock.signalSetGov(feePosiTracker.address, timelockV2.address)
    await timelock.signalSetGov(feePlpTracker.address, timelockV2.address)
    await timelock.signalSetGov(stakedPlpTracker.address, timelockV2.address)
    await timelock.signalSetGov(stakedPosiDistributor.address, timelockV2.address)
    await timelock.signalSetGov(stakedPlpDistributor.address, timelockV2.address)
    await timelock.signalSetGov(esPosi.address, timelockV2.address)
    await timelock.signalSetGov(bnPosi.address, timelockV2.address)
    await timelock.signalSetGov(posiVester.address, timelockV2.address)
    await timelock.signalSetGov(plpVester.address, timelockV2.address)
    console.log("RewardRouter.test.ts:1244", "set gove");

    await increaseTime(20)
    await mineBlock()

    await timelock.setGov(lpManager.address, timelockV2.address)
    await timelock.setGov(stakedPosiTracker.address, timelockV2.address)
    await timelock.setGov(bonusPosiTracker.address, timelockV2.address)
    await timelock.setGov(feePosiTracker.address, timelockV2.address)
    await timelock.setGov(feePlpTracker.address, timelockV2.address)
    await timelock.setGov(stakedPlpTracker.address, timelockV2.address)
    await timelock.setGov(stakedPosiDistributor.address, timelockV2.address)
    await timelock.setGov(stakedPlpDistributor.address, timelockV2.address)
    await timelock.setGov(esPosi.address, timelockV2.address)
    await timelock.setGov(bnPosi.address, timelockV2.address)
    await timelock.setGov(posiVester.address, timelockV2.address)
    await timelock.setGov(plpVester.address, timelockV2.address)

    await esPosi.setHandler(rewardRouterV2.address, true)
    await esPosi.setHandler(stakedPosiDistributor.address, true)
    await esPosi.setHandler(stakedPlpDistributor.address, true)
    await esPosi.setHandler(stakedPosiTracker.address, true)
    await esPosi.setHandler(stakedPlpTracker.address, true)
    await esPosi.setHandler(posiVester.address, true)
    await esPosi.setHandler(plpVester.address, true)
    console.log("RewardRouter.test.ts:1269", "set handlers");

    await lpManager.setHandler(rewardRouterV2.address, true)
    await stakedPosiTracker.setHandler(rewardRouterV2.address, true)
    await bonusPosiTracker.setHandler(rewardRouterV2.address, true)
    await feePosiTracker.setHandler(rewardRouterV2.address, true)
    await feePlpTracker.setHandler(rewardRouterV2.address, true)
    await stakedPlpTracker.setHandler(rewardRouterV2.address, true)
    console.log("RewardRouter.test.ts:1277", "after set handlers");

    await esPosi.setHandler(rewardRouterV2.address, true)
    await bnPosi.setMinter(rewardRouterV2.address, true)
    await esPosi.setMinter(posiVester.address, true)
    await esPosi.setMinter(plpVester.address, true)

    await posiVester.setHandler(rewardRouterV2.address, true)
    await plpVester.setHandler(rewardRouterV2.address, true)

    await feePosiTracker.setHandler(posiVester.address, true)
    await stakedPlpTracker.setHandler(plpVester.address, true)

    await eth.deposit({ value: expandDecimals(10, 18) })

    await posi.setMinter(wallet.address, true)
    await posi.mint(posiVester.address, expandDecimals(10000, 18))
    await posi.mint(plpVester.address, expandDecimals(10000, 18))

    await eth.mint(feePlpDistributor.address, expandDecimals(50, 18))
    await feePlpDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await eth.mint(feePosiDistributor.address, expandDecimals(50, 18))
    await feePosiDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))
    console.log("RewardRouter.test.ts:1301", "mint and stake");
    await rewardRouterV2.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )
    console.log("RewardRouter.test.ts:1308" , "mint and stake done");

    await posi.mint(user1.address, expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(expandDecimals(200, 18))
    await posi.connect(user1).approve(stakedPosiTracker.address, expandDecimals(200, 18))
    await rewardRouterV2.connect(user1).stakePosi(expandDecimals(200, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    expect(await posi.balanceOf(user1.address)).eq(0)
    expect(await esPosi.balanceOf(user1.address)).eq(0)
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).eq(0)

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).eq(0)
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).eq(0)

    await rewardRouterV2.connect(user1).handleRewards(
      true, // _shouldClaimPosi
      true, // _shouldStakePosi
      true, // _shouldClaimEsPosi
      true, // _shouldStakeEsPosi
      true, // _shouldStakeMultiplierPoints
      true, // _shouldClaimWeth
      false // _shouldConvertWethToEth
    )

    expect(await posi.balanceOf(user1.address)).eq(0)
    expect(await esPosi.balanceOf(user1.address)).eq(0)
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).gt(expandDecimals(7, 18))
    expect(await eth.balanceOf(user1.address)).lt(expandDecimals(8, 18))

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(3571, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(3572, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("540000000000000000") // 0.54
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("560000000000000000") // 0.56

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    const ethBalance0 = await provider.getBalance(user1.address)

    await rewardRouterV2.connect(user1).handleRewards(
      false, // _shouldClaimPosi
      false, // _shouldStakePosi
      false, // _shouldClaimEsPosi
      false, // _shouldStakeEsPosi
      false, // _shouldStakeMultiplierPoints
      true, // _shouldClaimWeth
      true // _shouldConvertWethToEth
    )

    const ethBalance1 = await provider.getBalance(user1.address)

    expect(await ethBalance1.sub(ethBalance0)).gt(expandDecimals(7, 18))
    expect(await ethBalance1.sub(ethBalance0)).lt(expandDecimals(8, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)
    expect(await esPosi.balanceOf(user1.address)).eq(0)
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).gt(expandDecimals(7, 18))
    expect(await eth.balanceOf(user1.address)).lt(expandDecimals(8, 18))

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(3571, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(3572, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("540000000000000000") // 0.54
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("560000000000000000") // 0.56

    await rewardRouterV2.connect(user1).handleRewards(
      false, // _shouldClaimPosi
      false, // _shouldStakePosi
      true, // _shouldClaimEsPosi
      false, // _shouldStakeEsPosi
      false, // _shouldStakeMultiplierPoints
      false, // _shouldClaimWeth
      false // _shouldConvertWethToEth
    )

    expect(await ethBalance1.sub(ethBalance0)).gt(expandDecimals(7, 18))
    expect(await ethBalance1.sub(ethBalance0)).lt(expandDecimals(8, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)
    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(3571, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(3572, 18))
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).gt(expandDecimals(7, 18))
    expect(await eth.balanceOf(user1.address)).lt(expandDecimals(8, 18))

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(3571, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(3572, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("540000000000000000") // 0.54
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("560000000000000000") // 0.56

    await posiVester.connect(user1).deposit(expandDecimals(365, 18))
    await plpVester.connect(user1).deposit(expandDecimals(365 * 2, 18))

    expect(await ethBalance1.sub(ethBalance0)).gt(expandDecimals(7, 18))
    expect(await ethBalance1.sub(ethBalance0)).lt(expandDecimals(8, 18))
    expect(await posi.balanceOf(user1.address)).eq(0)
    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(3571 - 365 * 3, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(3572 - 365 * 3, 18))
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).gt(expandDecimals(7, 18))
    expect(await eth.balanceOf(user1.address)).lt(expandDecimals(8, 18))

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(3571, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(3572, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("540000000000000000") // 0.54
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("560000000000000000") // 0.56

    await increaseTime(24 * 60 * 60)
    await mineBlock()

    await rewardRouterV2.connect(user1).handleRewards(
      true, // _shouldClaimPosi
      false, // _shouldStakePosi
      false, // _shouldClaimEsPosi
      false, // _shouldStakeEsPosi
      false, // _shouldStakeMultiplierPoints
      false, // _shouldClaimWeth
      false // _shouldConvertWethToEth
    )

    expect(await ethBalance1.sub(ethBalance0)).gt(expandDecimals(7, 18))
    expect(await ethBalance1.sub(ethBalance0)).lt(expandDecimals(8, 18))
    expect(await posi.balanceOf(user1.address)).gt("2900000000000000000") // 2.9
    expect(await posi.balanceOf(user1.address)).lt("3100000000000000000") // 3.1
    expect(await esPosi.balanceOf(user1.address)).gt(expandDecimals(3571 - 365 * 3, 18))
    expect(await esPosi.balanceOf(user1.address)).lt(expandDecimals(3572 - 365 * 3, 18))
    expect(await bnPosi.balanceOf(user1.address)).eq(0)
    expect(await plp.balanceOf(user1.address)).eq(0)
    expect(await eth.balanceOf(user1.address)).gt(expandDecimals(7, 18))
    expect(await eth.balanceOf(user1.address)).lt(expandDecimals(8, 18))

    expect(await stakedPosiTracker.depositBalances(user1.address, posi.address)).eq(expandDecimals(200, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).gt(expandDecimals(3571, 18))
    expect(await stakedPosiTracker.depositBalances(user1.address, esPosi.address)).lt(expandDecimals(3572, 18))
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).gt("540000000000000000") // 0.54
    expect(await feePosiTracker.depositBalances(user1.address, bnPosi.address)).lt("560000000000000000") // 0.56
  })

  it("StakedPlp", async () => {
    await eth.mint(feePlpDistributor.address, expandDecimals(100, 18))
    await feePlpDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))
    await rewardRouter.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))

    const stakedPlp = await deployContract("StakedPlp", [plp.address, lpManager.address, stakedPlpTracker.address, feePlpTracker.address])

    await expect(stakedPlp.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("StakedPlp: transfer amount exceeds allowance")

    await stakedPlp.connect(user1).approve(user2.address, expandDecimals(2991, 17))

    await expect(stakedPlp.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("StakedPlp: cooldown duration not yet passed")

    await increaseTime(24 * 60 * 60 + 10)
    await mineBlock()

    await expect(stakedPlp.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("RewardTracker: forbidden")

    await timelock.signalSetHandler(stakedPlpTracker.address, stakedPlp.address, true)
    await increaseTime(20)
    await mineBlock()
    await timelock.setHandler(stakedPlpTracker.address, stakedPlp.address, true)

    await expect(stakedPlp.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("RewardTracker: forbidden")

    await timelock.signalSetHandler(feePlpTracker.address, stakedPlp.address, true)
    await increaseTime(20)
    await mineBlock()
    await timelock.setHandler(feePlpTracker.address, stakedPlp.address, true)

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(0)

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(0)

    await stakedPlp.connect(user2).transferFrom(user1.address, user3. address, expandDecimals(2991, 17))

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(0)
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(0)

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(0)
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(0)

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))

    await expect(stakedPlp.connect(user2).transferFrom(user3.address, user1.address, expandDecimals(3000, 17)))
      .to.be.revertedWith("StakedPlp: transfer amount exceeds allowance")

    await stakedPlp.connect(user3).approve(user2.address, expandDecimals(3000, 17))

    await expect(stakedPlp.connect(user2).transferFrom(user3.address, user1.address, expandDecimals(3000, 17)))
      .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount")

    await stakedPlp.connect(user2).transferFrom(user3.address, user1.address, expandDecimals(1000, 17))

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(1000, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(1000, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(1000, 17))

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(1991, 17))
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(expandDecimals(1991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(1991, 17))
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(expandDecimals(1991, 17))

    await stakedPlp.connect(user3).transfer(user1.address, expandDecimals(1500, 17))

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2500, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2500, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2500, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2500, 17))

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(491, 17))
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(expandDecimals(491, 17))

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(expandDecimals(491, 17))
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(expandDecimals(491, 17))

    await expect(stakedPlp.connect(user3).transfer(user1.address, expandDecimals(492, 17)))
      .to.be.revertedWith("RewardTracker: _amount exceeds stakedAmount")

    expect(await bnb.balanceOf(user1.address)).eq(0)

    await rewardRouter.connect(user1).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(2500, 17),
      "830000000000000000", // 0.83
      user1.address
    )

    expect(await bnb.balanceOf(user1.address)).eq("830833333333333333")

    await usdp.addVault(lpManager.address)

    expect(await bnb.balanceOf(user3.address)).eq("0")

    await rewardRouter.connect(user3).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(491, 17),
      "160000000000000000", // 0.16
      user3.address
    )

    expect(await bnb.balanceOf(user3.address)).eq("163175666666666666")
  })

  it("FeePlp", async () => {
    await eth.mint(feePlpDistributor.address, expandDecimals(100, 18))
    await feePlpDistributor.setTokensPerInterval("41335970000000") // 0.00004133597 ETH per second

    await bnb.mint(user1.address, expandDecimals(1, 18))
    await bnb.connect(user1).approve(lpManager.address, expandDecimals(1, 18))
    await rewardRouter.connect(user1).mintAndStakePlp(
      bnb.address,
      expandDecimals(1, 18),
      expandDecimals(299, 18),
      expandDecimals(299, 18)
    )

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))

    const plpBalance = await deployContract("PlpBalance", [lpManager.address, stakedPlpTracker.address])

    await expect(plpBalance.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("PlpBalance: transfer amount exceeds allowance")

    await plpBalance.connect(user1).approve(user2.address, expandDecimals(2991, 17))

    await expect(plpBalance.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("PlpBalance: cooldown duration not yet passed")

    await increaseTime(24 * 60 * 60 + 10)
    await mineBlock()

    await expect(plpBalance.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17)))
      .to.be.revertedWith("RewardTracker: transfer amount exceeds allowance")

    await timelock.signalSetHandler(stakedPlpTracker.address, plpBalance.address, true)
    await increaseTime(20)
    await mineBlock()
    await timelock.setHandler(stakedPlpTracker.address, plpBalance.address, true)

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.balanceOf(user1.address)).eq(expandDecimals(2991, 17))

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(0)

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(0)
    expect(await stakedPlpTracker.balanceOf(user3.address)).eq(0)

    await plpBalance.connect(user2).transferFrom(user1.address, user3.address, expandDecimals(2991, 17))

    expect(await feePlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await feePlpTracker.depositBalances(user1.address, plp.address)).eq(expandDecimals(2991, 17))

    expect(await stakedPlpTracker.stakedAmounts(user1.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.depositBalances(user1.address, feePlpTracker.address)).eq(expandDecimals(2991, 17))
    expect(await stakedPlpTracker.balanceOf(user1.address)).eq(0)

    expect(await feePlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await feePlpTracker.depositBalances(user3.address, plp.address)).eq(0)

    expect(await stakedPlpTracker.stakedAmounts(user3.address)).eq(0)
    expect(await stakedPlpTracker.depositBalances(user3.address, feePlpTracker.address)).eq(0)
    expect(await stakedPlpTracker.balanceOf(user3.address)).eq(expandDecimals(2991, 17))

    await expect(rewardRouter.connect(user1).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(2991, 17),
      "0",
      user1.address
    )).to.be.revertedWith("RewardTracker: burn amount exceeds balance")

    await plpBalance.connect(user3).approve(user2.address, expandDecimals(3000, 17))

    await expect(plpBalance.connect(user2).transferFrom(user3.address, user1.address, expandDecimals(2992, 17)))
      .to.be.revertedWith("RewardTracker: transfer amount exceeds balance")

    await plpBalance.connect(user2).transferFrom(user3.address, user1.address, expandDecimals(2991, 17))

    expect(await bnb.balanceOf(user1.address)).eq(0)

    await rewardRouter.connect(user1).unstakeAndRedeemPlp(
      bnb.address,
      expandDecimals(2991, 17),
      "0",
      user1.address
    )

    expect(await bnb.balanceOf(user1.address)).eq("994009000000000000")
  })
})
