import { use } from "chai";
import { solidity } from "ethereum-waffle";
import {
  deployContractFixtures,
  loadMockTokenFixtures,
} from "../shared/fixtures";
import { ethers } from "hardhat";
import {
  MockToken,
  PriceFeed,
  Vault,
  VaultPriceFeedMock,
  WETH as IWETH,
} from "../../typeChain";
import { toChainlinkPrice } from "../shared/utilities";
import { BigNumber } from "ethers";

use(solidity);

describe("Vault.increasePosition", function () {
  let deployer: any;
  let trader: any;
  let trader2: any;

  let vault: Vault;
  let wethPriceFeed: PriceFeed;
  let busdPriceFeed: PriceFeed;
  let weth: IWETH;
  let busd: MockToken;

  beforeEach(async () => {
    const priceFeedMockFactory = await ethers.getContractFactory(
      "VaultPriceFeedMock"
    );
    const priceFeedMock =
      (await priceFeedMockFactory.deploy()) as unknown as VaultPriceFeedMock;

    const tokenFixtures = await loadMockTokenFixtures();
    const contractFixtures = await deployContractFixtures();

    vault = contractFixtures.vault;
    await vault.setPriceFeed(priceFeedMock.address);

    wethPriceFeed = tokenFixtures.wethPriceFeed as unknown as PriceFeed;
    busdPriceFeed = tokenFixtures.busdPriceFeed as unknown as PriceFeed;
    weth = tokenFixtures.WETH as unknown as IWETH;
    busd = tokenFixtures.busd as unknown as MockToken;

    // provider = contractFixtures.provider
    const users = await ethers.getSigners();
    deployer = users[0];
    trader = users[1];
    trader2 = users[2];
  });

  it.skip("test", async function () {
    await weth.connect(trader).deposit({
      value: ethers.utils.parseEther("100"),
    });
    await weth
      .connect(trader)
      .transfer(vault.address, ethers.utils.parseEther("100"));
    await wethPriceFeed.setLatestAnswer(toChainlinkPrice(1700));
    await vault.connect(trader).buyUSDP(weth.address, trader.address);

    await vault
      .connect(trader)
      .increasePosition(
        trader.address,
        weth.address,
        weth.address,
        BigNumber.from("100000000000000000000000"),
        true,
        BigNumber.from("1000000000000000000000")
      );
  });
});
