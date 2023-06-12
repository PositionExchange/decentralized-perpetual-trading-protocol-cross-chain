import { MigrationContext, MigrationDefinition } from "../types";
import {DptpFuturesGateway, GatewayUtils, WETH} from "../../typeChain";
import { BTCBUSD, ETHBUSD, LINKBUSD } from "../config_production";
import { ContractTransaction } from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy gateway utils": async () => {
      const vault = await ctx.factory.db.findAddressByKey("Vault");
      const futurXGateway = await ctx.factory.db.findAddressByKey("DptpFuturesGateway");
      const gatewayStorage = await ctx.factory.db.findAddressByKey("FuturXGatewayStorage");
      const futurXVoucher = await ctx.factory.db.findAddressByKey("FuturXVoucher");
      await ctx.factory.createGatewayUtils(vault, futurXGateway, gatewayStorage, futurXVoucher);
    },

    "re-config after deploy new gateway utils": async () => {
      const gatewayStorage = await ctx.factory.db.findAddressByKey("FuturXGatewayStorage");

      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
      const link = await ctx.factory.db.findAddressByKey("LINK");

      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>(
        "GatewayUtils"
      );

      const futurXGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>(
        "DptpFuturesGateway"
      );

      let tx: Promise<ContractTransaction>;

      tx = futurXGateway.setFuturXGatewayUtils(gatewayUtils.address);
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXGatewayUtils");

      // tx = gatewayUtils.setPositionManagerConfigData(
      //   wbtc,
      //   BTCBUSD.takerTollRatio,
      //   BTCBUSD.makerTollRatio,
      //   BTCBUSD.basisPoint,
      //   BTCBUSD.baseBasisPoint,
      //   BTCBUSD.contractPrice,
      //   BTCBUSD.assetRfiPercent,
      //   BTCBUSD.minimumOrderQuantity,
      //   BTCBUSD.stepBaseSize
      // );
      // await ctx.factory.waitTx(
      //   tx,
      //   "gatewayUtils.setPositionManagerConfigData.wbtc"
      // );
      //
      // tx = gatewayUtils.setPositionManagerConfigData(
      //   weth,
      //   ETHBUSD.takerTollRatio,
      //   ETHBUSD.makerTollRatio,
      //   ETHBUSD.basisPoint,
      //   ETHBUSD.baseBasisPoint,
      //   ETHBUSD.contractPrice,
      //   ETHBUSD.assetRfiPercent,
      //   ETHBUSD.minimumOrderQuantity,
      //   ETHBUSD.stepBaseSize
      // );
      // await ctx.factory.waitTx(
      //   tx,
      //   "gatewayUtils.setPositionManagerConfigData.weth"
      // );
      //
      // tx = gatewayUtils.setPositionManagerConfigData(
      //   link,
      //   LINKBUSD.takerTollRatio,
      //   LINKBUSD.makerTollRatio,
      //   LINKBUSD.basisPoint,
      //   LINKBUSD.baseBasisPoint,
      //   LINKBUSD.contractPrice,
      //   LINKBUSD.assetRfiPercent,
      //   LINKBUSD.minimumOrderQuantity,
      //   LINKBUSD.stepBaseSize
      // );
      // await ctx.factory.waitTx(
      //   tx,
      //   "gatewayUtils.setPositionManagerConfigData.link"
      // );
    },
  }),
};

export default migrations;
