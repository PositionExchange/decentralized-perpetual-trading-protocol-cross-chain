import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
  FuturXVoucher,
  GatewayUtils,
  ReferralRewardTracker,
  ReferralStorage,
  Vault
} from "../../typeChain";
import {ContractTransaction} from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx voucher": async () => {
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway")
      await ctx.factory.createFuturXVoucher(futurXGateway);
    },

    "re-config after deploy futurx voucher": async () => {
      const miners = [
        "0x4Ef2185384d2504B4CD944fCe7e6ad1a0c089E87"
      ]

      const futurXVoucher = await ctx.factory.getDeployedContract<FuturXVoucher>("FuturXVoucher")
      const futurXGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>("DptpFuturesGateway")
      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>("GatewayUtils")

      let tx: Promise<ContractTransaction>

      tx = futurXGateway.setFuturXVoucher(futurXVoucher.address)
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXVoucher")

      tx = gatewayUtils.setFuturXVoucher(futurXVoucher.address)
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXVoucher")

      for (let i = 0; i < miners.length; i++) {
        tx = futurXVoucher.addOperator(miners[i])
        await ctx.factory.waitTx(tx, "voucher.addOperator")
      }
    },
  }),
};

export default migrations;
