import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, WETH } from "../../typeChain";
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
      const managerBTC = "0x5f0b4df521b6b9c3b8366d5b67c50064178067a6";
      const managerETH = "0x338b4f4563b9a0ec2a07ad7338b43dc51674045e";
      const managerLINK = "0x218b17c430e5248571f543376f8875533af9f865";

      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
      const link = await ctx.factory.db.findAddressByKey("LINK");

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
    },
  }),
};

export default migrations;
