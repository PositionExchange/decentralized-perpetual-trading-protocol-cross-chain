import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway, FuturXGatewayStorage,
  FuturXVoucher,
  GatewayUtils,
  ReferralRewardTracker,
  ReferralStorage,
  Vault
} from "../../typeChain";
import {ContractTransaction} from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx gateway storage": async () => {
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway")
      await ctx.factory.createFuturXGatewayStorage(futurXGateway);
    },

    "re-config after deploy futurx gateway storage": async () => {
      const futurXGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>("DptpFuturesGateway")
      const futurXGatewayStorage = await ctx.factory.getDeployedContract<FuturXGatewayStorage>("FuturXGatewayStorage")

      let tx: Promise<ContractTransaction>

      tx = futurXGateway.setFuturXGatewayStorage(futurXGatewayStorage.address)
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXGatewayStorage")
    },
  }),
};

export default migrations;
