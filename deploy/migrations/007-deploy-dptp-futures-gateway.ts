import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
  FuturesAdapter,
  FuturXGatewayStorage,
  FuturXVoucher,
  GatewayUtils,
  ReferralRewardTracker,
  WETH,
} from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy dptp futures gateway": async () => {
      const chainId = ctx.hre.network.config.chainId || 0;
      const pscId = chainId == 42161 ? 900000 : 910000;
      const weth =
        chainId == 42161
          ? "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"
          : await ctx.factory.db.findAddressByKey("WETH");
      const vault = await ctx.factory.db.findAddressByKey("Vault");

      const futuresAdapter = await ctx.factory.db.findAddressByKey(
        "FuturesAdapter"
      );
      const gatewayUtils = await ctx.factory.db.findAddressByKey(
        "GatewayUtils"
      );
      const futurXGatewayStorage = await ctx.factory.db.findAddressByKey(
        "FuturXGatewayStorage"
      );

      await ctx.factory.createDptpFuturesGateway({
        pcsId: pscId,
        // TODO: Update pscCrossChainGateway by config mapping
        pscCrossChainGateway: "0x4b1573bc33a5d556C050D6F674B0924991ef0cdC",
        futuresAdapter: futuresAdapter,
        vault: vault,
        weth: weth,
        gatewayUtils: gatewayUtils,
        futurXGatewayStorage: futurXGatewayStorage,
        executionFee: 0,
      });

      // Create governance logic
      await ctx.factory.createFuturXGatewayGovernanceLogic();
    },

    "deploy tpsl gateway": async () => {
      await ctx.factory.createTPSLGateway();
    },

    "re-config after deploy new gateway": async () => {
      const managerBTC = "0x45a4a372df0cdc0fd81ec084a920364263a4fcb9";
      const managerETH = "0x67dc34ebff8b692c30c6afcc8f66bc38a89298b5";
      // const managerLINK = "0x19e6C8AB4b17c6e022D4c0EA8ac3f3FcBf4E91A7";

      const wbtc = "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f";
      const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
      // const link = await ctx.factory.db.findAddressByKey("LINK");

      const referralRewardTracker = await ctx.db.findAddressByKey(
        "ReferralRewardTracker"
      );

      const futuresGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );

      const futuresAdapter = await ctx.db.findAddressByKey("FuturesAdapter");

      const futurXGatewayStorage =
        await ctx.factory.getDeployedContract<FuturXGatewayStorage>(
          "FuturXGatewayStorage"
        );

      const futurXVoucher =
        await ctx.factory.getDeployedContract<FuturXVoucher>("FuturXVoucher");

      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>(
        "GatewayUtils"
      );

      let tx: Promise<ContractTransaction>;
      let data: number[];

      const abi = [
        "function setCoreManager(address _token, address _manager)",
        "function setPositionKeeper(address _address)",
        "function setReferralRewardTracker(address _address)",
        "function setPosiChainCrosschainGatewayContract(address _address)",
      ];

      data = encodeDelegateCall(abi, "setCoreManager", [wbtc, managerBTC]);
      tx = futuresGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.btc");

      data = encodeDelegateCall(abi, "setCoreManager", [weth, managerETH]);
      tx = futuresGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      // tx = futuresGateway.setCoreManager(link, managerLINK);
      // await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.link");

      // data = encodeDelegateCall(abi, "setPositionKeeper", [futuresAdapter]);
      // tx = futuresGateway.executeGovFunction(data);
      // await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");
      //
      // data = encodeDelegateCall(abi, "setReferralRewardTracker", [
      //   referralRewardTracker,
      // ]);
      // tx = futuresGateway.executeGovFunction(data);
      // await ctx.factory.waitTx(tx, "futuresGateway.setReferralRewardTracker");

      // data = encodeDelegateCall(abi, "setPosiChainCrosschainGatewayContract", [
      //   "0x4b1573bc33a5d556C050D6F674B0924991ef0cdC",
      // ]);
      // tx = futuresGateway.executeGovFunction(data);
      // await ctx.factory.waitTx(tx, "futuresGateway.setPosiChainCrosschainGatewayContract");

      // tx = futurXGatewayStorage.setFuturXGateway(futuresGateway.address);
      // await ctx.factory.waitTx(tx, "futurXGatewayStorage.setFuturXGateway");
      //
      // tx = futurXVoucher.setFuturXGateway(futuresGateway.address);
      // await ctx.factory.waitTx(tx, "futurXVoucher.setFuturXGateway");
      //
      // tx = gatewayUtils.setFuturXGateway(futuresGateway.address);
      // await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXGateway");
    },
  }),
};

export default migrations;
