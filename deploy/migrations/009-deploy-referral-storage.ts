import { MigrationContext, MigrationDefinition } from "../types";
import {ReferralRewardTracker, ReferralStorage, Vault} from "../../typeChain";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral storage": async () => {
      await ctx.factory.createReferralStorage();
    },

    "deploy referral reward tracker ": async () => {
      const referralStorage= await ctx.factory.db.findAddressByKey("ReferralStorage");
      const rewardToken = await ctx.factory.db.findAddressByKey("USDT");
      await ctx.factory.createReferralRewardTracker(
          {
            rewardToken,
            referralStorage,
          }
      );
    },

    "config after deploy referral reward tracker ": async () => {
      const referralStorage= await ctx.factory.getDeployedContract<ReferralStorage>("ReferralStorage");
      const referralRewardTracker = await ctx.factory.getDeployedContract<ReferralRewardTracker>("ReferralRewardTracker")
      const dptpFuturesGateway = await ctx.factory.db.findAddressByKey("DptpFuturesGateway");

      await ctx.factory.waitTx(
          referralStorage.setCounterParty(referralRewardTracker.address,true),
          "referralStorage.setCounterParty",
          true
      );

      await ctx.factory.waitTx(
          referralRewardTracker.setCounterParty(dptpFuturesGateway,true),
          "referralRewardTracker.setCounterParty",
          true
      );
    },
  }),
};

export default migrations;
