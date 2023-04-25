import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, MockToken, WETH } from "../../typeChain";
import { BTCBUSD, ETHBUSD } from "../config_production";
import {ContractTransaction} from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy dptp futures gateway": async () => {
      const vault = await ctx.factory.db.findAddressByKey("Vault");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
      const futuresAdapter = await ctx.factory.db.findAddressByKey(
        "FuturesAdapter"
      );

      await ctx.factory.createDptpFuturesGateway({
        pcsId: 910000,
        pscCrossChainGateway: "0xadf94555e5f2eae345692b8b39f062640e42b06f",
        futuresAdapter: futuresAdapter,
        vault: vault,
        weth: weth,
        executionFee: 0,
      });
    },

    're-config after deploy new gateway': async () => {
      const trader1 = "0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F";
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

      tx = futuresGateway.setPositionManagerConfigData(
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
        "futuresGateway.setPositionManagerConfigData.btc"
      );

      tx = futuresGateway.setCoreManager(weth, managerBTC);
      await ctx.factory.waitTx(tx, "futuresGateway.setCoreManager.eth");

      tx = futuresGateway.setPositionManagerConfigData(
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
        "futuresGateway.setPositionManagerConfigData.eth"
      );

      // tx = futuresGateway.setPositionKeeper(
      //   "0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F"
      // );
      // await ctx.factory.waitTx(tx, "futuresGateway.setPositionKeeper");
    },
  }),
};

export default migrations;
