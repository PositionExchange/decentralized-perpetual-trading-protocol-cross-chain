import { ethers } from "hardhat";
import {
  BEP20Mintable,
  DptpFuturesGateway,
  FuturesAdapterMock,
  FuturXGatewayStorage,
  FuturXVoucher,
  GatewayUtilsMock,
  ReferralRewardTrackerMock,
  ShortsTracker,
  VaultMock,
  WETH,
} from "../../typeChain";
import { BigNumber, ContractFactory } from "ethers";
import { parseUnits } from "@ethersproject/units/src.ts";

let deployer: any;
let trader: any;
let trader2: any;

// Target contract
let futurXGateway: DptpFuturesGateway;

// Mock Contracts
let vault: VaultMock;
let futuresAdapter: FuturesAdapterMock;
let shortsTracker: ShortsTracker;
let gatewayUtils: GatewayUtilsMock;
let referralRewardTracker: ReferralRewardTrackerMock;
let gatewayStorage: FuturXGatewayStorage;

// Tokens
let WETH: WETH;
let BTC: BEP20Mintable;
let BNB: BEP20Mintable;
let USDT: BEP20Mintable;

// NFT
let futurXVoucher: FuturXVoucher;

export async function deployContract() {
  // Get signers
  [deployer, trader, trader2] = await ethers.getSigners();

  let contractFactory: ContractFactory;

  /**
   * Deploy target contracts
   * */
  contractFactory = await ethers.getContractFactory("DptpFuturesGateway");
  futurXGateway =
    (await contractFactory.deploy()) as unknown as DptpFuturesGateway;
  await futurXGateway.deployed();

  /**
   * Deploy mock contracts
   * */
  contractFactory = await ethers.getContractFactory("VaultMock");
  vault = (await contractFactory.deploy()) as unknown as VaultMock;
  await vault.deployed();

  contractFactory = await ethers.getContractFactory("FuturesAdapterMock");
  futuresAdapter =
    (await contractFactory.deploy()) as unknown as FuturesAdapterMock;
  await futuresAdapter.deployed();

  contractFactory = await ethers.getContractFactory("ShortsTracker");
  shortsTracker = (await contractFactory.deploy(
    vault.address
  )) as unknown as ShortsTracker;
  await shortsTracker.deployed();

  contractFactory = await ethers.getContractFactory("GatewayUtilsMock");
  gatewayUtils =
    (await contractFactory.deploy()) as unknown as GatewayUtilsMock;
  await gatewayUtils.deployed();

  contractFactory = await ethers.getContractFactory(
    "ReferralRewardTrackerMock"
  );
  referralRewardTracker =
    (await contractFactory.deploy()) as unknown as ReferralRewardTrackerMock;
  await referralRewardTracker.deployed();

  contractFactory = await ethers.getContractFactory("FuturXGatewayStorage");
  gatewayStorage =
    (await contractFactory.deploy()) as unknown as FuturXGatewayStorage;
  await gatewayStorage.deployed();

  /**
   * Deploy tokens
   * */
  contractFactory = await ethers.getContractFactory("WETH");
  WETH = (await contractFactory.deploy("WETH", "WETH", 18)) as unknown as WETH;
  await WETH.deployed();

  contractFactory = await ethers.getContractFactory("BEP20Mintable");
  BTC = (await contractFactory.deploy(
    "BTC",
    "BTC"
  )) as unknown as BEP20Mintable;
  await BTC.deployed();

  BNB = (await contractFactory.deploy(
    "BNB",
    "BNB"
  )) as unknown as BEP20Mintable;
  await BNB.deployed();

  USDT = (await contractFactory.deploy(
    "USDT",
    "USDT"
  )) as unknown as BEP20Mintable;
  await USDT.deployed();

  /**
   * Deploy voucher
   * */
  contractFactory = await ethers.getContractFactory("FuturXVoucher");
  futurXVoucher = (await contractFactory.deploy()) as unknown as FuturXVoucher;
  await futurXVoucher.deployed();

  /**
   * Init contracts
   * */
  await futurXGateway.initialize(
    BigNumber.from("910000"),
    futuresAdapter.address,
    futuresAdapter.address,
    vault.address,
    WETH.address,
    gatewayUtils.address,
    gatewayStorage.address,
    ethers.utils.parseEther("0.02")
  );
  await gatewayStorage.initialize(futurXGateway.address);
  await futurXVoucher.initialize(futurXGateway.address, deployer.address);


  /**
   * Config contracts
   * */
  await vault.setTokenConfigurations(BTC.address, BigNumber.from("8"));
  await vault.setTokenConfigurations(WETH.address, BigNumber.from("18"));
  await vault.setTokenConfigurations(USDT.address, BigNumber.from("6"));

  await vault.setPriceMock(BTC.address, ethers.utils.parseUnits("27000", 30));
  await vault.setPriceMock(WETH.address, ethers.utils.parseUnits("1800", 30));
  await vault.setPriceMock(USDT.address, ethers.utils.parseUnits("1", 30));

  return [
    deployer,
    trader,
    trader2,
    futurXGateway,
    vault,
    futuresAdapter,
    shortsTracker,
    gatewayUtils,
    referralRewardTracker,
    gatewayStorage,
    WETH,
    BTC,
    BNB,
    USDT,
  ];
}

export async function mintAndApprove(trader) {
  await mint(trader);
  await approveContracts(trader);
}

export async function mint(trader) {
  await WETH.connect(trader).mint(
    trader.address,
    BigNumber.from("1000000000000000000") // 1 ETH
  );
  await BTC.connect(trader).mint(
    trader.address,
    BigNumber.from("100000000") // 1 BTC
  );
  await USDT.connect(trader).mint(
    trader.address,
    BigNumber.from("1000000000") // 1000 USDT
  );
}

export async function approveContracts(trader) {
  await WETH.connect(trader).approve(
    futurXGateway.address,
    BigNumber.from("1000000000000000000") // 1 ETH
  );
  await BTC.connect(trader).approve(
    futurXGateway.address,
    BigNumber.from("100000000") // 1 BTC
  );
  await USDT.connect(trader).approve(
    futurXGateway.address,
    BigNumber.from("1000000000") // 1000 USDT
  );
}
