import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway, FuturesAdapter, FuturXGatewayStorage, FuturXVoucher, GatewayUtils,
  ReferralRewardTracker,
  WETH,
} from "../../typeChain";
import { ContractTransaction } from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy dptp futures gateway": async () => {
      const vault = await ctx.factory.db.findAddressByKey("Vault");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
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
        pcsId: 910000,
        pscCrossChainGateway: "0x3230a2d25c81264F4e1A873729B53c62551Da792",
        futuresAdapter: futuresAdapter,
        vault: vault,
        weth: weth,
        gatewayUtils: gatewayUtils,
        futurXGatewayStorage: futurXGatewayStorage,
        executionFee: 0,
      });
    },

    "re-config after deploy new gateway": async () => {
      const managerBTC = "0x846d142804AF172c9a7Da38D82f26607C3EA2347";
      const managerETH = "0xf7A8a8971fCC59ca120Cd28F5079F09da29115cA";
      const managerLINK = "0x19e6C8AB4b17c6e022D4c0EA8ac3f3FcBf4E91A7";

      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
      const link = await ctx.factory.db.findAddressByKey("LINK");

      const referralRewardTracker =
        await ctx.factory.getDeployedContract<ReferralRewardTracker>(
          "ReferralRewardTracker"
        );

      const futuresGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );

      const futuresAdapter =
        await ctx.factory.getDeployedContract<FuturesAdapter>(
          "FuturesAdapter"
        );

      const futurXGatewayStorage =
        await ctx.factory.getDeployedContract<FuturXGatewayStorage>(
          "FuturXGatewayStorage"
        );

      const futurXVoucher =
        await ctx.factory.getDeployedContract<FuturXVoucher>(
          "FuturXVoucher"
        );

      const gatewayUtils =
        await ctx.factory.getDeployedContract<GatewayUtils>(
          "GatewayUtils"
        );

      let tx: Promise<ContractTransaction>;

      tx = futuresGateway.setCoreManager(wbtc, managerBTC);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.btc");

      tx = futuresGateway.setCoreManager(weth, managerETH);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      tx = futuresGateway.setCoreManager(link, managerLINK);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.link");

      tx = futuresGateway.setPositionKeeper(
          futuresAdapter.address
      );
      await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");

      tx = futuresGateway.setReferralRewardTracker(
          referralRewardTracker.address
      );
      await ctx.factory.waitTx(tx, "futuresGateway.setReferralRewardTracker");

      tx = futurXGatewayStorage.setFuturXGateway(
          futuresGateway.address
      );
      await ctx.factory.waitTx(tx, "futurXGatewayStorage.setFuturXGateway");

      tx = futurXVoucher.setFuturXGateway(
          futuresGateway.address
      );
      await ctx.factory.waitTx(tx, "futurXVoucher.setFuturXGateway");

      tx = gatewayUtils.setFuturXGateway(
          futuresGateway.address
      );
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXGateway");
    },
  }),
};

export default migrations;
