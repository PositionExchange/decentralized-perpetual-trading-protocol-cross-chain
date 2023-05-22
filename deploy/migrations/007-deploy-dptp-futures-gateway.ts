import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
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

      await ctx.factory.createDptpFuturesGateway({
        pcsId: 910000,
        pscCrossChainGateway: "0xadf94555e5f2eae345692b8b39f062640e42b06f",
        futuresAdapter: futuresAdapter,
        vault: vault,
        weth: weth,
        gatewayUtils: gatewayUtils,
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

      let tx: Promise<ContractTransaction>;

      tx = futuresGateway.setCoreManager(wbtc, managerBTC);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.btc");

      tx = futuresGateway.setCoreManager(weth, managerETH);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      tx = futuresGateway.setCoreManager(link, managerLINK);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.link");

      tx = futuresGateway.setPositionKeeper(
        "0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F"
      );
      await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");

      tx = futuresGateway.setReferralRewardTracker(
          referralRewardTracker.address
      );
      await ctx.factory.waitTx(tx, "futuresGateway.setReferralRewardTracker");
    },
  }),
};

export default migrations;
