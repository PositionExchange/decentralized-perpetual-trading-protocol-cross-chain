import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, GatewayUtils, WETH } from "../../typeChain";
import { BTCBUSD, ETHBUSD } from "../config_production";
import { ContractTransaction } from "ethers";
import {encodeDelegateCall} from "../shared/utils";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy gateway utils": async () => {
      const vault = await ctx.factory.db.findAddressByKey("Vault");
      const futurXGateway = await ctx.factory.db.findAddressByKey(
        "DptpFuturesGateway"
      );
      const gatewayStorage = await ctx.factory.db.findAddressByKey(
        "FuturXGatewayStorage"
      );
      const futurXVoucher = await ctx.factory.db.findAddressByKey(
        "FuturXVoucher"
      );
      await ctx.factory.createGatewayUtils(
        vault,
        futurXGateway,
        gatewayStorage,
        futurXVoucher
      );
    },

    "re-config after deploy new gateway utils": async () => {
      const gatewayStorage = await ctx.factory.db.findAddressByKey(
        "FuturXGatewayStorage"
      );

      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>(
        "GatewayUtils"
      );

      const futurXGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );

      let tx: Promise<ContractTransaction>;

      const data = encodeDelegateCall(
          ["function setFuturXGatewayUtils(address _address)"],
          "setFuturXGatewayUtils",
          [gatewayUtils.address]
      )
      tx = futurXGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXGatewayUtils");

      tx = gatewayUtils.setFuturXGatewayStorage(gatewayStorage);
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXGatewayStorage");

      tx = gatewayUtils.setPositionManagerConfigData(
        await ctx.factory.db.findAddressByKey("BTC"),
        BTCBUSD.takerTollRatio,
        BTCBUSD.makerTollRatio,
        BTCBUSD.basisPoint,
        BTCBUSD.baseBasisPoint,
        BTCBUSD.contractPrice,
        BTCBUSD.assetRfiPercent,
        BTCBUSD.minimumOrderQuantity,
        BTCBUSD.stepBaseSize
      );
      await ctx.factory.waitTx(tx, "gatewayUtils.configData.wbtc");

      tx = gatewayUtils.setPositionManagerConfigData(
        await ctx.factory.db.findAddressByKey("WETH"),
        ETHBUSD.takerTollRatio,
        ETHBUSD.makerTollRatio,
        ETHBUSD.basisPoint,
        ETHBUSD.baseBasisPoint,
        ETHBUSD.contractPrice,
        ETHBUSD.assetRfiPercent,
        ETHBUSD.minimumOrderQuantity,
        ETHBUSD.stepBaseSize
      );
      await ctx.factory.waitTx(tx, "gatewayUtils.configData.weth");
    },
  }),
};

export default migrations;
