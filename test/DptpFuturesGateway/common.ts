import { ethers } from "hardhat";
import {
  BEP20Mintable,
  DptpFuturesGatewayMock,
  FuturesAdapter,
  VaultMock,
  WETH,
} from "../../typeChain";
import { BigNumber } from "ethers";

export async function deployContract() {
  let deployer: any;
  let trader: any;
  let trader2: any;

  let vault: VaultMock;
  let futuresGateway: DptpFuturesGatewayMock;
  let futuresAdapter: FuturesAdapter;

  let weth: WETH;
  let whitelistedToken: BEP20Mintable;
  let notWhitelistedToken: BEP20Mintable;
  let stableToken: BEP20Mintable;

  [deployer, trader, trader2] = await ethers.getSigners();

  const wbnbFactory = await ethers.getContractFactory("WETH");
  weth = (await wbnbFactory.deploy("WETH", "WETH", 18)) as unknown as WETH;

  const bep20MintableFactory = await ethers.getContractFactory("BEP20Mintable");
  whitelistedToken = (await bep20MintableFactory.deploy(
    "whitelistedToken",
    "whitelistedToken"
  )) as unknown as BEP20Mintable;

  notWhitelistedToken = (await bep20MintableFactory.deploy(
    "notWhitelistedToken",
    "notWhitelistedToken"
  )) as unknown as BEP20Mintable;

  stableToken = (await bep20MintableFactory.deploy(
    "stableToken",
    "stableToken"
  )) as unknown as BEP20Mintable;

  const vaultMockFactory = await ethers.getContractFactory("VaultMock");
  vault = (await vaultMockFactory.deploy()) as unknown as VaultMock;

  // Deploy futures adapter
  const futuresAdapterFactory = await ethers.getContractFactory(
    "FuturesAdapter"
  );
  futuresAdapter =
    (await futuresAdapterFactory.deploy()) as unknown as FuturesAdapter;
  await futuresAdapter.initialize(910000, 86400);

  // Deploy futures gateway
  const futuresGatewayFactory = await ethers.getContractFactory(
    "DptpFuturesGatewayMock"
  );
  futuresGateway =
    (await futuresGatewayFactory.deploy()) as unknown as DptpFuturesGatewayMock;

  await futuresGateway.initialize(
    BigNumber.from("910000"),
    futuresAdapter.address,
    futuresAdapter.address,
    vault.address,
    weth.address,
    BigNumber.from("1000000000000000")
  );
  await futuresGateway.setPositionManagerConfigData(
    whitelistedToken.address,
    100,
    100,
    100,
    10000,
    0,
    0,
    0,
    0
  );
  await futuresGateway.setPositionManagerConfigData(
    weth.address,
    100,
    100,
    100,
    10000,
    0,
    0,
    0,
    0
  );

  await weth
    .connect(trader)
    .approve(futuresGateway.address, BigNumber.from("10000000000000000000"));
  await whitelistedToken
    .connect(trader)
    .approve(futuresGateway.address, BigNumber.from("10000000000000000000"));

  return [
    deployer,
    trader,
    trader2,
    vault,
    futuresGateway,
    futuresAdapter,
    weth,
    whitelistedToken,
    notWhitelistedToken,
    stableToken,
  ];
}
