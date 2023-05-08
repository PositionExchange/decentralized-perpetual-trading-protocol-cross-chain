import { MigrationContext, MigrationDefinition } from "../types";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral storage": async () => {
      const referralStorage = await ctx.factory.db.findAddressByKey(
        "ReferralStorage"
      );
      await ctx.factory.createReferralStorage(referralStorage);
    },
  }),
};

export default migrations;
