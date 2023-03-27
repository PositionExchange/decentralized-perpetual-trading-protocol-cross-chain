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
} from "../../typeChain";
import { BigNumber } from "ethers";

use(solidity);

describe("Vault.increasePosition", function () {
  let deployer: any;
  let trader: any;
  let trader2: any;

  let vault: Vault;
  let btcPriceFeed: PriceFeed;
  let daiPriceFeed: PriceFeed;
  let btc: MockToken;
  let dai: MockToken;

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

    btcPriceFeed = tokenFixtures.btcPriceFeed as unknown as PriceFeed;
    daiPriceFeed = tokenFixtures.daiPriceFeed as unknown as PriceFeed;
    btc = tokenFixtures.btc as unknown as MockToken;
    dai = tokenFixtures.dai as unknown as MockToken;

    // provider = contractFixtures.provider
    const users = await ethers.getSigners();
    deployer = users[0];
    trader = users[1];
    trader2 = users[2];
  });

  it.skip("test", async function () {
    await vault
      .connect(trader)
      .increasePosition(
        trader.address,
        btc.address,
        btc.address,
        BigNumber.from("100000000000000000000000"),
        true,
        BigNumber.from("1000000000000000000000")
      );
  });
});
