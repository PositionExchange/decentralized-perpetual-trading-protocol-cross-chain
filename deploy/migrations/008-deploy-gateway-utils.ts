import { MigrationContext, MigrationDefinition } from "../types";
import { GatewayUtils, WETH } from "../../typeChain";
import { BTCBUSD, ETHBUSD } from "../config_production";
import { ContractTransaction } from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy gateway utils": async () => {
      const vault = await ctx.factory.db.findAddressByKey("Vault");
      await ctx.factory.createGatewayUtils(vault);
    },

    "re-config after deploy new gateway utils": async () => {
      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");

      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>(
        "GatewayUtils"
      );

      let tx: Promise<ContractTransaction>;

      tx = gatewayUtils.setPositionManagerConfigData(
        wbtc,
        BTCBUSD.takerTollRatio,
        BTCBUSD.makerTollRatio,
        BTCBUSD.basisPoint,
        BTCBUSD.baseBasisPoint,
        BTCBUSD.contractPrice,
        BTCBUSD.assetRfiPercent,
        BTCBUSD.minimumOrderQuantity,
        BTCBUSD.stepBaseSize
      );
      await ctx.factory.waitTx(
        tx,
        "gatewayUtils.setPositionManagerConfigData.btc"
      );

      tx = gatewayUtils.setPositionManagerConfigData(
        weth,
        ETHBUSD.takerTollRatio,
        ETHBUSD.makerTollRatio,
        ETHBUSD.basisPoint,
        ETHBUSD.baseBasisPoint,
        ETHBUSD.contractPrice,
        ETHBUSD.assetRfiPercent,
        ETHBUSD.minimumOrderQuantity,
        ETHBUSD.stepBaseSize
      );
      await ctx.factory.waitTx(
        tx,
        "gatewayUtils.setPositionManagerConfigData.eth"
      );
    },
  }),
};

export default migrations;
