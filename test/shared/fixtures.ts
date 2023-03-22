import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployMockContract } from "ethereum-waffle";
import { ethers } from "hardhat";
import { Vault, VaultPriceFeed__factory, VaultUtils__factory } from "../../typeChain";
import { deployContract, toChainlinkPrice, toPriceFeedPrice } from "./utilities";

export async function mockTokenFixtures() {
  const MockTokenFactory = await ethers.getContractFactory("MockToken");
  const initialAmount = ethers.utils.parseEther("1000000");

  const dummyToken = await MockTokenFactory.deploy(initialAmount, "DummyToken", "DUMMY", 18);
  const busd = await MockTokenFactory.deploy(initialAmount, "Mock BUSD", "BUSD", 18);
  const usdt = await MockTokenFactory.deploy(initialAmount, "Mock USDT", "USDT", 9);
  const WETH = await MockTokenFactory.deploy(initialAmount, "Mock WETH", "WETH", 18);

  const USDPFactory = await ethers.getContractFactory("USDP");
  const usdp = await USDPFactory.deploy();

  return { dummyToken, busd, usdt, WETH, usdp, createToken: (name: string, symbol: string, decimals = 18) => {
    return MockTokenFactory.deploy(initialAmount,name, symbol, decimals);
  }};
}

export async function deployContractFixtures() {
  const [deployer, user1, user2, user3] = await ethers.getSigners();
  const {busd, usdt, WETH, usdp} = await loadFixture(mockTokenFixtures)
  const mockVaultUtils = await deployMockContract(deployer, JSON.stringify(VaultUtils__factory.abi))
  const mockVaultPriceFeed = await deployMockContract(deployer, JSON.stringify(VaultPriceFeed__factory.abi))
  const vault = await deployContract<Vault>("Vault", [
    mockVaultUtils.address,
    mockVaultPriceFeed.address,
    usdp.address,
  ]);
  await usdp.addVault(vault.address);
  // init vault
  // set whitelist caller
  await vault.setWhitelistCaller(deployer.address, true);

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

  await mockVaultUtils.mock.getBuyUsdgFeeBasisPoints.returns(100) // 1%

  async function setPrice(token: string, price: string | number, isMaximize: boolean = false) {
    await mockVaultPriceFeed.mock.getPrice.withArgs(token, isMaximize).returns(toPriceFeedPrice(price))
  }


  return {
    mockVaultPriceFeed,
    deployer,
    user1,
    user2,
    user3,
    vault,
    setPrice,
  }
}

// @dev care fully dealling with load  fixtures, it will reset the state to the initial state in every call
// So if you call const {vault} = await loadContractFixtures()
// ...your logic
// then call const {vault} = await loadContractFixtures() -- the vault state will be reset to the initial state here
// See more: https://hardhat.org/tutorial/testing-contracts#reusing-common-test-setups-with-fixtures
export const loadContractFixtures = () => loadFixture(deployContractFixtures)
export const loadMockTokenFixtures = () => loadFixture(mockTokenFixtures)
