import {
  BEP20Mintable,
  DptpFuturesGateway,
  FuturesAdapterMock,
  FuturXGatewayStorage,
  GatewayUtilsMock,
  ReferralRewardTrackerMock,
  ShortsTracker,
  VaultMock,
  WETH,
} from "../../typeChain";
import { deployContract, mintAndApprove } from "./common";
import { BigNumber, ContractTransaction, ethers } from "ethers";
import { ContractReceipt } from "@ethersproject/contracts/src.ts";
import { expect } from "chai";

describe.only("FuturX Gateway createIncreaseOrder", async function () {
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

  beforeEach(async () => {
    [
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
    ] = await deployContract();
  });

  it("given valid request, when calling createIncreasePositionRequest, should success", async () => {
    await mintAndApprove(trader);

    const balanceBefore = await BTC.balanceOf(trader.address);

    const params = {
      path: [BTC.address],
      indexToken: BTC.address,
      amountInUsd: ethers.utils.parseEther("270"),
      sizeDeltaToken: ethers.utils.parseEther("0.1"),
      leverage: BigNumber.from("10"),
      isLong: true,
      voucherId: 0,
    };
    const tx: ContractTransaction = await futurXGateway
      .connect(trader)
      .createIncreasePositionRequest(
        params.path,
        params.indexToken,
        params.amountInUsd,
        params.sizeDeltaToken,
        params.leverage,
        params.isLong,
        params.voucherId
      );
    const receipt: ContractReceipt = await tx.wait();
    // TODO: verify logs

    const balanceAfter = await BTC.balanceOf(trader.address);
    expect(balanceBefore.sub(balanceAfter)).eq(1000000);
  });

  it("given valid request, when calling createIncreaseOrderRequest, should success", async () => {
    await mintAndApprove(trader);

    const balanceBefore = await BTC.balanceOf(trader.address);

    const params = {
      path: [BTC.address],
      indexToken: BTC.address,
      amountInUsd: ethers.utils.parseEther("270"),
      pip: BigNumber.from("2700000"),
      sizeDeltaToken: ethers.utils.parseEther("0.1"),
      leverage: BigNumber.from("10"),
      isLong: true,
      voucherId: 0,
    };
    const tx: ContractTransaction = await futurXGateway
      .connect(trader)
      .createIncreaseOrderRequest(
        params.path,
        params.indexToken,
        params.amountInUsd,
        params.pip,
        params.sizeDeltaToken,
        params.leverage,
        params.isLong,
        params.voucherId
      );
    const receipt: ContractReceipt = await tx.wait();
    // TODO: verify logs

    const balanceAfter = await BTC.balanceOf(trader.address);
    expect(balanceBefore.sub(balanceAfter)).eq(1000000);
  });
});
