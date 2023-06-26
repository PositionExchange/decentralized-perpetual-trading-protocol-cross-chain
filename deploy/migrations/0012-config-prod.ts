import { run } from "hardhat";
import { MigrationContext, MigrationDefinition } from "../types";
import { SUBTASK_NAME } from "../tasks/common";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "PROD vault set futurX gateway": async () => {
      const chainId = ctx.hre.network.config.chainId || 0;
      if (chainId != 42161) return;

      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
      await run(SUBTASK_NAME.VAULT_SetFuturXGateway, {
        ctx: ctx,
        futurXGateway,
      });
    },
  }),
};

export default migrations;
