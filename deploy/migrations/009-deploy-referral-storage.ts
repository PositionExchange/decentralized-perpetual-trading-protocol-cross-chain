import { MigrationContext, MigrationDefinition } from "../types";
import { GatewayUtils, WETH } from "../../typeChain";
import { BTCBUSD, ETHBUSD, LINKBUSD } from "../config_production";
import { ContractTransaction } from "ethers";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral storage": async () => {
      const referralStorage = await ctx.factory.db.findAddressByKey("ReferralStorage");
      await ctx.factory.createReferralStorage(referralStorage);
    },
  }),
};

export default migrations;
