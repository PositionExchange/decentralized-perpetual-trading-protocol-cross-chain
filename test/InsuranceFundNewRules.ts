// import {ethers} from "hardhat";
// import {BEP20Mintable, InsuranceFundTest, FuturesGateway} from "../typeChain";
// import {BigNumber} from "ethers";
// import {expect} from "chai";
// import BigNumberJs from "bignumber.js";
//
// require("it-each")();
//
// describe('Insurance Fund New Rules', async function () {
//     this.timeout(1000000);
//     let deployer: any;
//     let insuranceFund: InsuranceFundTest;
//     let positionManager: any;
//     let busdToken: BEP20Mintable;
//     let busdBonusToken: BEP20Mintable;
//     let trader: any;
//
//     class BalanceChangeTrack {
//         balanceBefore: BigNumberJs = new BigNumberJs(0);
//
//         constructor(private token: BEP20Mintable, private trackAddress: string) {
//         }
//
//         async getBalance() {
//             return new BigNumberJs(
//                 await this.token.balanceOf(this.trackAddress).then((value) => {
//                     return ethers.utils.formatEther(value);
//                 })
//             );
//         }
//
//         async track() {
//             this.balanceBefore = await this.getBalance();
//         }
//
//         async expectChange(expectChange: string | number, label?: string) {
//             const balanceAfter = await this.getBalance();
//             const change = balanceAfter.minus(this.balanceBefore).toString();
//             console.log(
//                 `Balance change: ${change.toString()}, after: ${balanceAfter.toString()}, before: ${this.balanceBefore.toString()}`
//             );
//             expect(Number(change)).to.equal(
//                 Number(expectChange),
//                 `Expect ${label}, is not as expect. Expected balance: ${expectChange}, actual balance: ${balanceAfter}`
//             );
//             this.balanceBefore = balanceAfter;
//         }
//     }
//
//     beforeEach(async () => {
//         [deployer, trader, positionManager] = await ethers.getSigners()
//
//         // Deploy mock busd contract
//         const bep20MintableFactory = await ethers.getContractFactory('BEP20Mintable')
//         busdToken = (await bep20MintableFactory.deploy('BUSD Mock', 'BUSD')) as unknown as BEP20Mintable
//
//         // Deploy mock credit contract
//         busdBonusToken = (await bep20MintableFactory.deploy('BUSD Bonus Mock', 'BUSDBONUS')) as unknown as BEP20Mintable
//
//         const factory = await ethers.getContractFactory("InsuranceFundTest")
//         insuranceFund = (await factory.deploy()) as unknown as InsuranceFundTest
//         await insuranceFund.initialize();
//         await insuranceFund.setBonusAddress(busdBonusToken.address)
//         await insuranceFund.setCounterParty(deployer.address)
//         await insuranceFund.updateWhitelistManager(positionManager.getAddress(), true)
//         await insuranceFund.shouldAcceptBonus(true)
//         await insuranceFund.setManagerAssetMapping(positionManager.getAddress(), busdToken.address)
//
//         await busdToken.connect(trader).increaseAllowance(insuranceFund.address, BigNumber.from('100000000000000000000000000'))
//         await busdBonusToken.connect(trader).increaseAllowance(insuranceFund.address, BigNumber.from('100000000000000000000000000'))
//
//         await busdToken.mint(deployer.getAddress(), BigNumber.from('100000000000000000000000000'))
//         await busdBonusToken.mint(deployer.getAddress(), BigNumber.from('1000000000000000001000'))
//
//         await busdToken.mint(insuranceFund.address, BigNumber.from('100000000000000000000000000'))
//         await busdBonusToken.mint(insuranceFund.address, BigNumber.from('1000000000000000001000'))
//
//
//         // Reset trader balance
//         const traderBalance = await busdToken.balanceOf(trader.getAddress())
//         if (traderBalance.gt(BigNumber.from('0'))) {
//             await busdToken.connect(trader).burn(traderBalance)
//         }
//
//         // Set InsuranceFund BUSD balance
//         await busdToken.connect(deployer).transfer(insuranceFund.address, BigNumber.from('10000'))
//
//         // Set InsuranceFund BUSD Bonus balance
//         await busdBonusToken.connect(deployer).transfer(insuranceFund.address, BigNumber.from('1000'))
//
//         // Set Trader BUSD balance
//         await busdToken.mint(trader.getAddress(), BigNumber.from('0'))
//
//         // Set Trader bonus balance in InsuranceFund
//         await insuranceFund.connect(deployer).setBonusBalance(positionManager.getAddress(), trader.getAddress(), BigNumber.from('10'))
//
//         // Default is
//         // Bonus balance in insurance fund = 10
//         // Bonus balance in wallet fund = 0
//         // BUSD balance in wallet = 0
//     })
//
//     const testCalculateBusdBonusAmount = async (depositamount: string, notional: string, expectValue: [busdAmount: string, busdBonusAmount: string], _trader = deployer) => {
//         // busd bonus balance
//         const busdBonusBalance = await busdBonusToken.balanceOf(_trader.address)
//         console.log(`busdBonusBalance: ${busdBonusBalance.toString()}`)
//         const amount = ethers.utils.parseEther(depositamount)
//         const fee = BigNumber.from(amount).mul(1).div(10000)
//         const [collectableBUSDAmount, depositedBonusAmountWithFee, depositedBonusAmountWithOutFee] = await insuranceFund.connect(_trader).calculateBusdBonusAmount(
//             positionManager.getAddress(),
//             _trader.getAddress(),
//             amount,
//             fee,
//             ethers.utils.parseEther(notional)
//         )
//         expect(collectableBUSDAmount.toString()).to.equal(ethers.utils.parseEther(expectValue[0]).toString())
//         expect(depositedBonusAmountWithOutFee.toString()).to.equal(ethers.utils.parseEther(expectValue[1]).toString())
//     }
//
//     function toWei(n: number | string): any {
//         return BigNumber.from(ethers.utils.parseEther(n.toString()))
//     }
//
//     const depositWithBusdBonus = async (_realInitialMargin: string, _bonusInitialMargin: string, _notional: string, _trader = deployer) => {
//         const busdBonusBalance = await busdBonusToken.balanceOf(_trader.address)
//         console.log(`busdBonusBalance: ${busdBonusBalance.toString()}`)
//         const realInitialMargin = ethers.utils.parseEther(_realInitialMargin)
//         const bonusInitialMargin = ethers.utils.parseEther(_bonusInitialMargin)
//         const notional = ethers.utils.parseEther(_notional)
//         const fee = BigNumber.from(notional).mul(1).div(10000)
//
//         await insuranceFund.connect(_trader).depositWithBonus(positionManager.address, _trader.address, realInitialMargin, bonusInitialMargin, fee)
//     }
//
//     // loop each data
//     // it.each([])(`should calculate busd bonus correct`, async function (notional, busdAmount, busdBonus, expected) {
//     //
//     // })
//
//
//     it('should calculate busd bonus correct', async function () {
//         /*
//         * 1. Trader has 0 BUSD in wallet
//         * 2. Trader has 10 BUSD bonus in InsuranceFund
//          */
//         /*
//        if notional
//             <=500 BUSD then use busdBonus 90%, 10% for busdAmount
//             // same as above
//             <=1000 BUSD	70%
//             <=10000 BUSD	50%
//             <=200000 BUSD	30%
//             <300000 BUSD	20%
//             >300000 BUSD	10%
//         */
//
//         await testCalculateBusdBonusAmount('10', '500', ['3', '7'])
//         await testCalculateBusdBonusAmount('10', '400', ['3', '7'])
//         await testCalculateBusdBonusAmount('10', '600', ['4', '6'])
//         await testCalculateBusdBonusAmount('10', '1000', ['4', '6'])
//         await testCalculateBusdBonusAmount('10', '5000', ['6', '4'])
//         await testCalculateBusdBonusAmount('10', '12000', ['7.5', '2.5'])
//         await testCalculateBusdBonusAmount('10', '25000', ['8.5', '1.5'])
//         await testCalculateBusdBonusAmount('10', '35000', ['9.5', '0.5'])
//         await testCalculateBusdBonusAmount('10', '3500000000', ['9.5', '0.5'])
//         // do not have busd bonus
//         await testCalculateBusdBonusAmount('10', '35000', ['10', '0'], trader)
//         await testCalculateBusdBonusAmount('1200', '5000', ['800', '400'])
//     });
//
//     it('should withdraw busd when having profit', async () => {
//         await insuranceFund.setCounterParty(deployer.address)
//         await busdToken.connect(deployer).approve(insuranceFund.address, ethers.utils.parseEther('1000000000'))
//         await busdBonusToken.connect(deployer).approve(insuranceFund.address, ethers.utils.parseEther('1000000000'))
//         await testCalculateBusdBonusAmount('10', '1000', ['4', '6'])
//         console.log("line 138")
//         await depositWithBusdBonus('4', '6', '1000')
//         console.log("line 140")
//         const busdBonusBeforeWithdraw = await busdBonusToken.balanceOf(deployer.address)
//         const busdBeforeWithdraw = await busdToken.balanceOf(deployer.address)
//         console.log("line 143")
//         await insuranceFund.withdraw(positionManager.address, deployer.address, ethers.utils.parseEther('15'))
//         console.log("line 145")
//         const busdBonusAfterWithdraw = await busdBonusToken.balanceOf(deployer.address)
//         const busdAfterWithdraw = await busdToken.balanceOf(deployer.address)
//         await expect(busdBonusAfterWithdraw.sub(busdBonusBeforeWithdraw).toString()).eq(toWei('6').toString())
//         await expect(busdAfterWithdraw.sub(busdBeforeWithdraw).toString()).eq(toWei('9').toString())
//         console.log('busd bonus exchanged', busdBonusAfterWithdraw.sub(busdBonusBeforeWithdraw).toString())
//         console.log('busd exchanged', busdAfterWithdraw.sub(busdBeforeWithdraw).toString())
//     })
//
//     beforeEach(async () => {
//         await busdToken.connect(deployer).approve(insuranceFund.address, ethers.utils.parseEther('1000000000'))
//         await busdBonusToken.connect(deployer).approve(insuranceFund.address, ethers.utils.parseEther('1000000000'))
//     })
//     it('should test accept max maximumBUSDBonusAcceptedPerPosition', async function () {
//         await insuranceFund.updateMaximumBUSDBonusAcceptedPerPosition(ethers.utils.parseEther('100'))
//
//         const balanceTrackingBUSD = new BalanceChangeTrack(busdToken, deployer.address)
//         const balanceTrackingBUSD_Bonus = new BalanceChangeTrack(busdBonusToken, deployer.address)
//         await balanceTrackingBUSD.track()
//         await balanceTrackingBUSD_Bonus.track()
//         // deposit 100 BUSD, 90 BUSD bonus
//         await depositWithBusdBonus('100', '90', '100')
//         await balanceTrackingBUSD.expectChange(-100.01)
//         await balanceTrackingBUSD_Bonus.expectChange(-90)
//         // now deposit more 100 BUSD, 90 BUSD bonus
//         await depositWithBusdBonus('100', '90', '100')
//         // only cost 10 BUSD bonus, the rest should cost BUSD
//         await balanceTrackingBUSD.expectChange(-180.01)
//         await balanceTrackingBUSD_Bonus.expectChange(-10)
//         // now deposit more 100 BUSD, 90 BUSD bonus
//         await depositWithBusdBonus('100', '90', '100')
//         // should not accept more than 100 BUSD bonus
//         await balanceTrackingBUSD.expectChange(-190.01)
//         await balanceTrackingBUSD_Bonus.expectChange(0)
//
//     });
//
//     it('should test with initial bonus balance > maximum', async function () {
//         const balanceTrackingBUSD = new BalanceChangeTrack(busdToken, deployer.address)
//         const balanceTrackingBUSD_Bonus = new BalanceChangeTrack(busdBonusToken, deployer.address)
//         await balanceTrackingBUSD.track()
//         await balanceTrackingBUSD_Bonus.track()
//         await depositWithBusdBonus('100', '110', '100')
//         await insuranceFund.updateMaximumBUSDBonusAcceptedPerPosition(ethers.utils.parseEther('100'))
//         await balanceTrackingBUSD.expectChange(-100.01)
//         await balanceTrackingBUSD_Bonus.expectChange(-110)
//         // now deposit more 100 BUSD, 90 BUSD bonus
//         await depositWithBusdBonus('100', '90', '100')
//         // should not accept more than 100 BUSD bonus
//         await balanceTrackingBUSD.expectChange(-190.01)
//         await balanceTrackingBUSD_Bonus.expectChange(0)
//     });
//
// })
