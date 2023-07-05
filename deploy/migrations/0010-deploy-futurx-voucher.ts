import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
  FuturXVoucher,
  GatewayUtils,
} from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";
import { run } from "hardhat";
import { SUBTASK_NAME } from "../tasks/common";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx voucher": async () => {
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
      const signer = "0x019685D1202CcDBd5c5AC02a2150e408C6148ce1";
      await ctx.factory.createFuturXVoucher(futurXGateway, signer);
    },

    "re-config after deploy futurx voucher": async () => {
      const futurXVoucher =
        await ctx.factory.getDeployedContract<FuturXVoucher>("FuturXVoucher");
      const futurXGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );
      const gatewayUtils = await ctx.factory.getDeployedContract<GatewayUtils>(
        "GatewayUtils"
      );

      await run(SUBTASK_NAME.FGW_SetFuturXVoucher, {
        ctx: ctx,
      });

      let tx: Promise<ContractTransaction>;

      // tx = gatewayUtils.setFuturXVoucher(futurXVoucher.address);
      // await ctx.factory.waitTx(tx, "gatewayUtils.setFuturXVoucher");
    },
  }),
};

export default migrations;
