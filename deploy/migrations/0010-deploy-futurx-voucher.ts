import { MigrationContext, MigrationDefinition } from "../types";
import {DptpFuturesGateway, ReferralRewardTracker, ReferralStorage, Vault} from "../../typeChain";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx voucher": async () => {
      await ctx.factory.createFuturXVoucher("0x4Ef2185384d2504B4CD944fCe7e6ad1a0c089E87");
    },
  }),
};

export default migrations;
