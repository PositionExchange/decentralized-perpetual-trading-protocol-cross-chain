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
      const managerBTC = "0xe727a7e1f6bdcd9470a3577e264b9eb4e377f990";
      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");

      const futuresGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );

      let tx: Promise<ContractTransaction>;

      tx = futuresGateway.setCoreManager(wbtc, managerBTC);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.btc");

      tx = futuresGateway.setCoreManager(weth, managerBTC);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      tx = futuresGateway.setPositionKeeper(
        "0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F"
      );
      await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");
    },
  }),
};

export default migrations;
