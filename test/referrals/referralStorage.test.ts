import { expect } from "chai"
import { ethers } from "hardhat"
import {ReferralStorage} from "../../typeChain";

const { AddressZero, HashZero } = ethers.constants
describe("ReferralStorage", function() {
  let deployer: any
  let referralStorage : ReferralStorage
  let admin: any
  let user: any
  let user1: any

  beforeEach(async () => {
    [deployer,admin, user, user1] = await ethers.getSigners()

    const referralStorageFactory = await ethers.getContractFactory("ReferralStorage")
    referralStorage = (await referralStorageFactory.deploy()) as ReferralStorage
    await referralStorage.initialize();
  })

  it("setTier", async () => {
    await expect(referralStorage.connect(user).setTier(0, 1000, 5000))
        .to.be.revertedWith("Ownable: caller is not the owner")
    await expect(referralStorage.setTier(0, 10001, 5000))
        .to.be.revertedWith("ReferralStorage: invalid totalRebate")
    await expect(referralStorage.setTier(0, 1000, 10001))
        .to.be.revertedWith("ReferralStorage: invalid discountShare")
    await referralStorage.connect(deployer).setTier(1,500,500)
    const tier1 = await referralStorage.tiers(1)
    expect(tier1.totalRebate).eq(500)
    expect(tier1.discountShare).eq(500)
  })

  it("setAdmin", async () => {
    await expect(referralStorage.connect(user).setAdmin(admin.address, true))
        .to.be.revertedWith("Ownable: caller is not the owner")

    expect(await referralStorage.isAdmin(admin.address)).to.be.false
    await referralStorage.setAdmin(admin.address, true)
    expect(await referralStorage.isAdmin(admin.address)).to.be.true

    await referralStorage.setAdmin(admin.address, false)
    expect(await referralStorage.isAdmin(admin.address)).to.be.false
  })

  it("registerCode", async () => {
      expect(await referralStorage.traderCodes(user.address)).eq(HashZero)
      const code = ethers.utils.formatBytes32String('ABC_123')
      expect (await referralStorage.codes(code)).eq(AddressZero)

      await referralStorage.connect(user).registerCode(code);
      expect (await referralStorage.codes(code)).eq(user.address)
      expect (await referralStorage.traderCodes(user.address)).eq(code)

      expect (referralStorage.connect(user).registerCode(code)).
        to.be.revertedWith("ReferralStorage: trader already has code")

      expect (referralStorage.connect(user1).registerCode(code)).
        to.be.revertedWith("ReferralStorage: code already exists")
  })

  it.only("setTraderReferralCode", async () => {
      const nonUserCode = ethers.utils.formatBytes32String('123_ABC')
      const userCode = ethers.utils.formatBytes32String('A1B2C3')
      await referralStorage.connect(user).registerCode(userCode);
      const refCode = ethers.utils.formatBytes32String('ABC_123')
      await referralStorage.connect(user1).registerCode(refCode);

      expect(await referralStorage.traderReferralCodes(user.address)).eq(HashZero)
      expect(referralStorage.connect(user).setTraderReferralCode(nonUserCode)).
        to.be.revertedWith("ReferralStorage: referrer not exists")

      expect(referralStorage.connect(user).setTraderReferralCode(userCode)).
        to.be.revertedWith("ReferralStorage: self referred")

      await referralStorage.setAdmin(admin.address, true)
      await referralStorage.connect(admin).setReferrerTier(user.address, 2)
      expect(referralStorage.connect(user).setTraderReferralCode(userCode)).
        to.be.revertedWith("ReferralStorage: must less than referrer tier")
      await referralStorage.connect(admin).setReferrerTier(user.address, 1)

      await referralStorage.connect(user).setTraderReferralCode(refCode)
      expect(await referralStorage.traderReferralCodes(user.address)).eq(refCode)
  })
})
