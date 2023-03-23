import { smock } from "@defi-wonderland/smock";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployMockContract } from "ethereum-waffle";
import { ethers } from "hardhat";
import { Vault, VaultPriceFeed, VaultPriceFeed__factory, VaultUtils__factory } from "../../typeChain";
import { getBnbConfig } from "./config";
import { deployContract, toChainlinkPrice, toPriceFeedPrice } from "./utilities";

export async function mockTokenFixtures() {
  const address2Name = {}
  const MockTokenFactory = await ethers.getContractFactory("MockToken");
  const initialAmount = ethers.utils.parseEther("1000000");

  const dummyToken = await MockTokenFactory.deploy(initialAmount, "DummyToken", "DUMMY", 18);
  const busd = await MockTokenFactory.deploy(initialAmount, "Mock BUSD", "BUSD", 18);
  const usdt = await MockTokenFactory.deploy(initialAmount, "Mock USDT", "USDT", 9);
  const dai = await MockTokenFactory.deploy(initialAmount, "Mock DAI", "DAI", 8);
  const WBNB = await MockTokenFactory.deploy(initialAmount, "Mock WBNB", "BNB", 18);
  const WETH = await MockTokenFactory.deploy(initialAmount, "Mock WETH", "WETH", 18);

  const PriceFeedFactory = await ethers.getContractFactory("PriceFeed");

  const busdPriceFeed = await PriceFeedFactory.deploy()
  const usdtPriceFeed = await PriceFeedFactory.deploy()
  const wethPriceFeed = await PriceFeedFactory.deploy()
  const bnbPriceFeed = await PriceFeedFactory.deploy()
  const daiPriceFeed = await PriceFeedFactory.deploy()

  const USDPFactory = await ethers.getContractFactory("USDP");
  const usdp = await USDPFactory.deploy();

  address2Name[usdp.address] = "USDP";
  address2Name[busd.address] = "BUSD";
  address2Name[usdt.address] = "USDT";
  address2Name[WETH.address] = "WETH";
  address2Name[WBNB.address] = "WBNB";
  address2Name[dai.address] = "DAI";
  

  return { dummyToken, address2Name, busdPriceFeed, daiPriceFeed, bnbPriceFeed, usdtPriceFeed, wethPriceFeed, busd, usdt, WETH, weth: WETH, usdp, WBNB, bnb: WBNB, eth: WETH, dai, createToken: (name: string, symbol: string, decimals = 18) => {
    return MockTokenFactory.deploy(initialAmount,name, symbol, decimals);
  }};
}

export async function deployVaultPureFixtures() {
  const [deployer, user1, user2, user3 ] = await ethers.getSigners();
  const {busd, usdt, dai, bnb, WETH, usdp, busdPriceFeed, usdtPriceFeed, wethPriceFeed, bnbPriceFeed, daiPriceFeed} = await loadFixture(mockTokenFixtures)
  // const mockVaultUtils = await deployMockContract(deployer, JSON.stringify(VaultUtils__factory.abi))
  const mockVaultUtilsFactory = await ethers.getContractFactory("VaultUtils") //smock.mock<VaultUtils__factory>('VaultUtils');
  const mockVaultUtils = await mockVaultUtilsFactory.deploy();
  const vaultPriceFeedFactory = await ethers.getContractFactory("VaultPriceFeed");
  const mockVaultPriceFeed = (await vaultPriceFeedFactory.deploy()) as VaultPriceFeed

  mockVaultPriceFeed.setPriceFeedConfig(busd.address, busdPriceFeed.address, 8, 0)
  mockVaultPriceFeed.setPriceFeedConfig(usdt.address, usdtPriceFeed.address, 8, 0)
  mockVaultPriceFeed.setPriceFeedConfig(WETH.address, wethPriceFeed.address, 8, 0)
  mockVaultPriceFeed.setPriceFeedConfig(dai.address, daiPriceFeed.address, 8, 0)
  mockVaultPriceFeed.setPriceFeedConfig(bnb.address, bnbPriceFeed.address, 8, 0)

  const vault = await deployContract<Vault>("Vault", [
    mockVaultUtils.address,
    mockVaultPriceFeed.address,
    usdp.address,
  ]);

  await mockVaultUtils.initialize(vault.address);

  await usdp.addVault(vault.address);
  // init vault
  // set whitelist caller
  await vault.setWhitelistCaller(deployer.address, true);

  // await mockVaultUtils.getBuyUsdgFeeBasisPoints.returns(100) // 1%
  // await mockVaultUtils.getSellUsdgFeeBasisPoints.returns(100) // 1%

  return {vault, mockVaultPriceFeed, mockVaultUtils}
}

export async function deployContractFixtures() {
  const [deployer, user1, user2, user3 ] = await ethers.getSigners();
  const {busd, usdt, dai, bnb, WETH} = await loadFixture(mockTokenFixtures)
  const {vault, mockVaultPriceFeed, mockVaultUtils} = await loadFixture(deployVaultPureFixtures)
  // init default for busd, usd and weth
  await vault.setConfigToken(
    busd.address,
    18,
    // min profit bps
    1000,
    1,
    ethers.utils.parseEther("100000"),
    true,
    false
  );
  await vault.setConfigToken(
    usdt.address,
    18,
    // min profit bps
    1000,
    1,
    ethers.utils.parseEther("100000"),
    true,
    false
  );
  await vault.setConfigToken(
    WETH.address,
    18,
    // min profit bps
    1000,
    1,
    ethers.utils.parseEther("100000"),
    true,
    true
  );
  //@ts-ignore
  await vault.setConfigToken(...getBnbConfig(bnb))
  //@ts-ignore
  await vault.setConfigToken(...getBnbConfig(dai))


  return {
    mockVaultPriceFeed,
    deployer,
    user0: deployer,
    user1,
    user2,
    user3,
    vault,
  }
}


// @dev care fully dealling with load  fixtures, it will reset the state to the initial state in every call
// So if you call const {vault} = await loadContractFixtures()
// ...your logic
// then call const {vault} = await loadContractFixtures() -- the vault state will be reset to the initial state here
// See more: https://hardhat.org/tutorial/testing-contracts#reusing-common-test-setups-with-fixtures
export const loadContractFixtures = () => loadFixture(deployContractFixtures)
export const loadVaultPureFixtures = () => loadFixture(deployVaultPureFixtures)
export const loadMockTokenFixtures = () => loadFixture(mockTokenFixtures)
