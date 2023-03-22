import { ethers, waffle} from 'hardhat';
import {BEP20Mintable, InsuranceFundTest, FuturesGatewayMock, FuturesAdapter} from "../typeChain";
import {BigNumber} from "ethers";
import {expect, use} from "chai";
const {solidity} = waffle
use(solidity)

const toWei = (amount: string): BigNumber => ethers.utils.parseEther(amount)

describe('Futures Gateway', async function () {
    let deployer: any;
    let insuranceFund: InsuranceFundTest;
    let futuresGateway: FuturesGatewayMock;
    let futuresAdapter: FuturesAdapter;
    let busdToken: BEP20Mintable;
    let busdBonusToken: BEP20Mintable;
    let trader: any;
    let trader2: any;
    let crosschainGateway: any;
    let usdmManager: any;
    let coinmManager: any;
    class TrackBalance {
        busdBalance = BigNumber.from('0')
        busdBonusBalance = BigNumber.from('0')
        constructor(private trader: string) {
        }
        async track(log: boolean = false) {
            this.busdBalance = await busdToken.balanceOf(this.trader)
            this.busdBonusBalance = await busdBonusToken.balanceOf(this.trader)
            if (log) {
                console.log('[Track balance] Latest balance', this.trader, this.format())
            }
        }
        async getChange() {
            const currentBusd = await busdToken.balanceOf(this.trader)
            const currentBonus = await busdBonusToken.balanceOf(this.trader)
            const currentDiff = {
                busd: this.busdBalance.sub(currentBusd),
                busdBonus: this.busdBonusBalance.sub(currentBonus)
            }
            this.busdBalance = currentBusd
            this.busdBonusBalance = currentBonus
            return currentDiff
        }
        async expectChange(busd: string | number, busdBonus: string | number) {
            const currentDiff = await this.getChange()
            expect(currentDiff.busd.toString()).eq(toWei(busd.toString()).toString())
            expect(currentDiff.busdBonus.toString()).eq(toWei(busdBonus.toString()).toString())
        }
        format(){
            return {
                busd: ethers.utils.formatEther(this.busdBalance),
                busdBonus: ethers.utils.formatEther(this.busdBonusBalance)
            }
        }
    }
    beforeEach(async () => {
        [deployer, trader, trader2, crosschainGateway, usdmManager, coinmManager] = await ethers.getSigners()

        // Deploy mock busd contract
        const bep20MintableFactory = await ethers.getContractFactory('BEP20Mintable')
        busdToken = (await bep20MintableFactory.deploy('BUSD Mock', 'BUSD')) as unknown as BEP20Mintable
        // Deploy mock credit contract
        busdBonusToken = (await bep20MintableFactory.deploy('BUSD Bonus Mock', 'BUSDBONUS')) as unknown as BEP20Mintable

        // Deploy futures adapter
        const futuresAdapterFactory = await ethers.getContractFactory("FuturesAdapter")
        futuresAdapter = (await futuresAdapterFactory.deploy()) as unknown as FuturesAdapter
        await futuresAdapter.initialize(910000,86400)

        // Deploy insuranceFund
        const factory = await ethers.getContractFactory("InsuranceFundTest")
        insuranceFund = (await factory.deploy()) as unknown as InsuranceFundTest
        await insuranceFund.initialize();
        await insuranceFund.updateWhitelistManager(usdmManager.address, true)
        await insuranceFund.setManagerAssetMapping(usdmManager.address,busdToken.address)
        await insuranceFund.updateWhitelistManager(coinmManager.address, true)
        await insuranceFund.setManagerAssetMapping(coinmManager.address,busdToken.address)
        await insuranceFund.setBonusAddress(busdBonusToken.address)
        await insuranceFund.shouldAcceptBonus(true)

        // Deploy futures gateway
        const futuresGatewayFactory = await ethers.getContractFactory("FuturesGatewayMock")
        futuresGateway = (await futuresGatewayFactory.deploy()) as unknown as FuturesGatewayMock

        await  futuresGateway.initialize(futuresAdapter.address,crosschainGateway.address,910000, insuranceFund.address)
        await futuresGateway.setPositionManagerConfigData(usdmManager.address, 100, 100, 100, 10000, 0, 0,0, 0)
        await futuresGateway.setPositionManagerConfigData(coinmManager.address,100,100,100,10000,1000,0,0, 0)
        await insuranceFund.setCounterParty(futuresGateway.address)

        await busdToken.mint(trader.getAddress(), ethers.utils.parseEther('10000'))
        await busdToken.connect(trader).approve(insuranceFund.address,BigNumber.from('10000'))

        await busdToken.mint(trader2.getAddress(), BigNumber.from('10000'))
        await busdToken.connect(trader2).approve(insuranceFund.address,BigNumber.from('10000'))

        await busdBonusToken.mint(trader.getAddress(), BigNumber.from('1000000000000000000000'))

        await busdToken.connect(trader).increaseAllowance(insuranceFund.address, BigNumber.from('100000000000000000000000000'))
        await busdBonusToken.connect(trader).increaseAllowance(insuranceFund.address, BigNumber.from('100000000000000000000000000'))

    })

    describe("test deposit", async () => {
        beforeEach(async () => {
            await insuranceFund.shouldAcceptBonus(false)
        })

        it("[usd-m] tollRatio is 0, should deposit quantity only", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            // Set Trader BUSD balance

            let price = await futuresGateway.pipToPriceTest(usdmManager.address,2200000)
            expect(price.toString()).eq('220000000')
            let notional = await futuresGateway.calcNotionalTest(usdmManager.address, price,1)
            expect(notional.toString()).eq('22000')
            let marginfee = await futuresGateway.calcMarginAndFeeTest(usdmManager.address,BigNumber.from(1),2200000,10)
            expect(marginfee.fee).eq(220)
            expect(marginfee.margin).eq(2200)
            // Trader deposit
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                2200000,
                10,
                2200,
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit).eq("7580")
            expect(insuranceFundBalance).eq("2420")
        })

        it("[usd-m] tollRatio is 0.001%, should deposit quantity and fee", async () => {
            await futuresGateway.updateManagerTakerTollRatio(usdmManager.address, 10000)
            await futuresGateway.updateManagerMakerTollRatio(usdmManager.address, 10000)
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            let price = await futuresGateway.pipToPriceTest(usdmManager.address,2200000)
            expect(price.toString()).eq('220000000')
            let notional = await futuresGateway.calcNotionalTest(usdmManager.address, price,1)
            expect(notional).eq(22000)
            let marginfee = await futuresGateway.calcMarginAndFeeTest(usdmManager.address,BigNumber.from(1),2200000,10)
            expect(marginfee.fee).eq(2)
            expect(marginfee.margin).eq(2200)
            // Trader deposit
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                2200000,
                10,
                2202,
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit).eq("7796")
            expect(insuranceFundBalance).eq("2204")
        })

        it("[coin-m] tollRatio is 0, should deposit quantity only", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            let price = await futuresGateway.pipToPriceTest(coinmManager.address,2200000)
            expect(price.toString()).eq('220000000')
            let notional = await futuresGateway.calcNotionalTest(coinmManager.address, price,220)
            expect(notional).eq(10)
            let marginfee = await futuresGateway.calcMarginAndFeeTest(coinmManager.address,220,2200000,10)
            expect(marginfee.fee).eq(0)
            expect(marginfee.margin).eq(1)
            // Trader deposit
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                coinmManager.getAddress(),
                1,
                220,
                2200000,
                10,
                1,
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit).eq("9999")
            expect(insuranceFundBalance).eq("1")
        })

        it("[coin-m] tollRatio is 1%, should deposit quantity and fee", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            await futuresGateway.updateManagerMakerTollRatio(coinmManager.address, 100)
            await futuresGateway.updateManagerTakerTollRatio(coinmManager.address, 100)

            let price = await futuresGateway.pipToPriceTest(coinmManager.address,2200000)
            expect(price.toString()).eq('220000000')
            let notional = await futuresGateway.calcNotionalTest(coinmManager.address, price,2200)
            expect(notional).eq(100)
            let marginfee = await futuresGateway.calcMarginAndFeeTest(coinmManager.address,2200,2200000,10)
            expect(marginfee.fee).eq(1)
            expect(marginfee.margin).eq(10)
            // Trader deposit
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                coinmManager.getAddress(),
                1,
                2200,
                2200000,
                10,
                11,
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit).eq("9988")
            expect(insuranceFundBalance).eq("12")
        })

        it("add margin, should deposit successfully", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            // Trader deposit
            await futuresGateway.connect(trader).functions["addMargin(address,uint256,uint256)"](
                usdmManager.getAddress(),
                BigNumber.from(2000),
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit.toString()).eq("8000")
            expect(insuranceFundBalance).eq("2000")
        })

        it("add margin with rfi, should deposit successfully", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            await futuresGateway.setManagerAssetRFI(usdmManager.address,1)

            // Trader deposit
            await futuresGateway.connect(trader).functions["addMargin(address,uint256,uint256)"](
                usdmManager.getAddress(),
                BigNumber.from(2000),
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            expect(traderBUSDBalanceAfterDeposit.toString()).eq("7980")
        })

        it("user send valid quantity, should deposit sucessfully", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            await futuresGateway.setMinimumOrderQuantity(usdmManager.address, 0)
            // Trader deposit
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                2200000,
                10,
                2200,
                0
            )

            const traderBUSDBalanceAfterDeposit = await busdToken.balanceOf(trader.getAddress())
            const insuranceFundBalance = await busdToken.balanceOf(insuranceFund.address);
            expect(traderBUSDBalanceAfterDeposit.toString()).eq("7580")
            expect(insuranceFundBalance.toString()).eq("2420")
        })

        it("user send invalid quantity, should not deposit successfully", async () => {
            await futuresGateway.setMinimumOrderQuantity(usdmManager.address, 1000)

            // Trader deposit
            await expect(futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                1,
                2200000,
                10,
                2200,
                0
            )).to.revertedWith('3')
        })

        it("should validate minimum order quantity only open order, not close order", async () => {
            await futuresGateway.setMinimumOrderQuantity(usdmManager.address, 1000)

            await expect(futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                800,
                2200000,
                10,
                2200,
                0
            )).to.revertedWith('3')

            await expect(futuresGateway.connect(trader).functions["openMarketOrder(address,uint8,uint256,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                700,
                10,
                2200,
                0
            )).to.revertedWith('3')

            await expect(futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                1100,
                2200000,
                10,
                2200,
                0
            ))

            await expect(futuresGateway.connect(trader).functions["openMarketOrder(address,uint8,uint256,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                1700,
                10,
                2200,
                0
            ))

            await expect(futuresGateway.connect(trader).closeLimitPosition(
                usdmManager.getAddress(),
                1,
                500,
            ))

            await expect(futuresGateway.connect(trader).closeMarketPosition(
                usdmManager.getAddress(),
                500
            ))

            await expect(futuresGateway.connect(trader).instantlyClosePosition(
                usdmManager.getAddress(),
                500
            ))
        })

        it("should charge different fee rate for taker and maker", async () => {
            await busdToken.connect(trader).burn(ethers.utils.parseEther('10000'))
            await busdToken.mint(trader.address, BigNumber.from('10000'))

            // maker fee is 1%
            await futuresGateway.updateManagerMakerTollRatio(usdmManager.address, 100)
            // taker fee is 2%
            await futuresGateway.updateManagerTakerTollRatio(usdmManager.address, 50)

            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                2000000,
                10,
                2000,
                0
            )

            const traderBalanceAfterOpenLimit = await busdToken.balanceOf(trader.getAddress())
            // expect balance of trader = 10000 - 2000 - 2000 * 10 (leverage) * 1% (maker fee) = 7800
            expect(traderBalanceAfterOpenLimit.toString()).eq("7800")

            await futuresGateway.connect(trader2).functions["openMarketOrder(address,uint8,uint256,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                0,
                BigNumber.from(1),
                10,
                2000,
                0
            )

            const trader2BalanceAfterOpenMarket = await busdToken.balanceOf(trader2.getAddress())
            // expect balance of trader = 10000 - 2000 - 2000 * 10 (leverage) * 2% (taker fee) = 7600
            expect(trader2BalanceAfterOpenMarket.toString()).eq("7600")
        })
    })

    describe("test with new rules busd bonus", async () => {
        /*
        test1: User open long market, quantity is 1, price is 2000000, leverage is 10, initial margin 2000
        should deposit deposit 300 BUSD Bonus + 1700 BUSD real
         */

        it("should deposit margin > busd bonus", async () => {
            const balanceTracking = new TrackBalance(trader.address)
            await balanceTracking.track()
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                2000000,
                10,
                ethers.utils.parseEther("2000"),
                ethers.utils.parseEther("250")

            )
            await balanceTracking.expectChange(1950, 250)
        })
        it("should deposit margin = busd bonus", async () => {
            const balanceTracking = new TrackBalance(trader.address)
            await balanceTracking.track(true)
            await futuresGateway.connect(trader).functions["openMarketOrder(address,uint8,uint256,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                10,
                ethers.utils.parseEther("1000"),
                ethers.utils.parseEther("400")

            )
            await balanceTracking.expectChange(700, 400)
            console.log("latest balance", balanceTracking.format())
        })
        it("should deposit margin < busd bonus", async () => {
            const balanceTracking = new TrackBalance(trader.address)
            await balanceTracking.track(true)
            await futuresGateway.connect(trader).functions["openMarketOrder(address,uint8,uint256,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
                BigNumber.from(1),
                10,
                ethers.utils.parseEther("60"),
                ethers.utils.parseEther("36")
            )
            await balanceTracking.expectChange(30, 36)
        })
        it("should deposit margin < busd bonus, but not enough", async () => {
            const balanceTracking = new TrackBalance(trader.address)
            await balanceTracking.track(true)
            await futuresGateway.connect(trader).functions["openLimitOrder(address,uint8,uint256,uint128,uint16,uint256,uint256)"](
                usdmManager.getAddress(),
                1,
               '5000000000000000',
                2000000,
                10,
                '10000000000000000000',
                '7000000000000000000'
            )
            await balanceTracking.expectChange(4, 7)
        })

    })
});

