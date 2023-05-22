import { expect } from "chai"
import { ethers } from "hardhat"
import {ReferralRewardTracker, ReferralStorage} from "../../typeChain";
describe("ReferralRewardTracker", function() {
  let deployer: any
  let busd : any
  let referralStorage : ReferralStorage
  let referralRewardTracker : ReferralRewardTracker
  let admin: any
  let referee: any
  let referrer: any

  beforeEach(async () => {
    [deployer,admin, referee, referrer] = await ethers.getSigners();

    const MockTokenFactory = await ethers.getContractFactory("MockToken");
    const initialAmount = ethers.utils.parseEther("1000000");
    busd = await MockTokenFactory.deploy(initialAmount, "Mock BUSD", "BUSD", 18);

    const referralStorageFactory = await ethers.getContractFactory("ReferralStorage")
    referralStorage = (await referralStorageFactory.deploy()) as ReferralStorage
    await referralStorage.initialize();

    await referralStorage.setTier(1,500,500)
    const refCode = ethers.utils.formatBytes32String('ABC_123')
    await referralStorage.connect(referrer).registerCode(refCode);
    await referralStorage.connect(referee).setTraderReferralCode(refCode)

    const referralRewardTrackerFactory = await ethers.getContractFactory("ReferralRewardTracker")
    referralRewardTracker = (await referralRewardTrackerFactory.deploy()) as ReferralRewardTracker
    await referralRewardTracker.initialize(busd.address, referralStorage.address);

    await referralStorage.setCounterParty(admin.address, true)
    await referralRewardTracker.setCounterParty(admin.address, true)
    await busd.mint(referralRewardTracker.address, initialAmount)

    await referralStorage.setCounterParty(referralRewardTracker.address, true);
  })

  it("updateClaimableReward", async () => {
    expect(referralRewardTracker.connect(referee).updateClaimableReward(referee.address,ethers.utils.parseEther("1"))).
    to.be.revertedWith("ReferralStorage: onlyCounterParty")
    // refereeCodes status is pending
    await referralRewardTracker.connect(admin).updateClaimableReward(referee.address,ethers.utils.parseEther("1"))
    expect(await referralRewardTracker.claimableCommission(referrer.address)).to.be.equal(0)
    expect(await referralRewardTracker.claimableDiscount(referee.address)).to.be.equal(0)
    // referee status is active
    await referralStorage.connect(admin).setTraderStatus(referee.address, true);
    await referralRewardTracker.connect(admin).updateClaimableReward(referee.address,ethers.utils.parseEther("1"))
    const claimableCommission = await referralRewardTracker.claimableCommission(referrer.address)
    const claimableDiscount = await referralRewardTracker.claimableDiscount(referee.address)
    expect(claimableCommission.toString()).eq("50000000000000000")
    expect(claimableDiscount.toString()).eq("50000000000000000")
  })

  it("updateRefereeStatus", async () => {
    expect(await referralStorage.traderStatus(referee.address)).to.be.false
    const time = Math.round(Date. now() / 1000)

    // while hold time did not reach validation interval
    await referralRewardTracker.connect(admin).updateRefereeStatus(
        referee.address,busd.address,time,ethers.utils.parseEther("100"), true)
    await referralRewardTracker.connect(admin).updateRefereeStatus(
        referee.address,busd.address,time+100, 0, false)
    expect(await referralStorage.traderStatus(referee.address)).to.be.false

    // while hold time reach validation interval
    await referralRewardTracker.connect(admin).updateRefereeStatus(
        referee.address,busd.address,time, ethers.utils.parseEther("100"), true)
    await referralRewardTracker.connect(admin).updateRefereeStatus(
        referee.address,busd.address,time+2000,0, false)
    expect(await referralStorage.traderStatus(referee.address)).to.be.true
  })
})
