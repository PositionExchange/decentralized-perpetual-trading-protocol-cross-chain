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
        pscCrossChainGateway: "0x0000000000000000000000000000000000000000",
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
      // const managerBTC = "0x846d142804AF172c9a7Da38D82f26607C3EA2347";
      // const managerETH = "0xf7A8a8971fCC59ca120Cd28F5079F09da29115cA";
      // const managerLINK = "0x19e6C8AB4b17c6e022D4c0EA8ac3f3FcBf4E91A7";

      // const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      // const weth = await ctx.factory.db.findAddressByKey("WETH");
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

      // tx = futuresGateway.setCoreManager(wbtc, managerBTC);
      // await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.btc");

      // tx = futuresGateway.setCoreManager(weth, managerETH);
      // await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      // tx = futuresGateway.setCoreManager(link, managerLINK);
      // await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.link");

      const abi = [
        "function setPositionKeeper(address _address)",
        "function setReferralRewardTracker(address _address)",
      ];
      let data = encodeDelegateCall(abi, "setPositionKeeper", [futuresAdapter]);
      tx = futuresGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");

      data = encodeDelegateCall(abi, "setReferralRewardTracker", [
        referralRewardTracker,
      ]);
      tx = futuresGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futuresGateway.setReferralRewardTracker");

      tx = futurXGatewayStorage.setFuturXGateway(futuresGateway.address);
      await ctx.factory.waitTx(tx, "futurXGatewayStorage.setFuturXGateway");

      tx = futurXVoucher.setFuturXGateway(futuresGateway.address);
      await ctx.factory.waitTx(tx, "futurXVoucher.setFuturXGateway");

      tx = gatewayUtils.setFuturXGateway(futuresGateway.address);
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXGateway");
    },
  }),
};

export default migrations;
