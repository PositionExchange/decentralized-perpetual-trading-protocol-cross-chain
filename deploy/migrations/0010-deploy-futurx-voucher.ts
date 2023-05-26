import { MigrationContext, MigrationDefinition } from "../types";
import {DptpFuturesGateway, GatewayUtils, ReferralRewardTracker, ReferralStorage, Vault} from "../../typeChain";
import {ContractTransaction} from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx voucher": async () => {
      await ctx.factory.createFuturXVoucher("0x4Ef2185384d2504B4CD944fCe7e6ad1a0c089E87");
    },

    "re-config after deploy futurx voucher": async () => {
      const futurXVoucher = await ctx.db.findAddressByKey("FuturXVoucher")
      const futurXGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>("DptpFuturesGateway")
      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>("GatewayUtils")

      let tx: Promise<ContractTransaction>

      tx = futurXGateway.setFuturXVoucher(futurXVoucher)
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXVoucher")

      tx = gatewayUtils.setFuturXVoucher(futurXVoucher)
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXVoucher")
    },
  }),
};

export default migrations;
