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
      const signer = "0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F"

      await ctx.factory.createFuturXVoucher(futurXGateway, signer);
    },

    "re-config after deploy futurx voucher": async () => {
      const futurXVoucher = await ctx.factory.getDeployedContract<FuturXVoucher>("FuturXVoucher")
      const futurXGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>("DptpFuturesGateway")
      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>("GatewayUtils")

      let tx: Promise<ContractTransaction>

      tx = futurXGateway.setFuturXVoucher(futurXVoucher.address)
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXVoucher")

      tx = gatewayUtils.setFuturXVoucher(futurXVoucher.address)
      await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXVoucher")
    },
  }),
};

export default migrations;
