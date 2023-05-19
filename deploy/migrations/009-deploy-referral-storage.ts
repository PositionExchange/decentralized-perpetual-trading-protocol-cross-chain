import { MigrationContext, MigrationDefinition } from "../types";
import {DptpFuturesGateway, ReferralRewardTracker, ReferralStorage, Vault} from "../../typeChain";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral storage": async () => {
      await ctx.factory.createReferralStorage();
    },

    "deploy referral reward tracker": async () => {
      const referralStorage= await ctx.factory.db.findAddressByKey("ReferralStorage");
      const rewardToken = await ctx.factory.db.findAddressByKey("USDT");
      await ctx.factory.createReferralRewardTracker(
          {
            rewardToken,
            referralStorage,
          }
      );
    },

    "config after deploy referral reward tracker": async () => {
      const referralStorage= await ctx.factory.getDeployedContract<ReferralStorage>("ReferralStorage");
      const referralRewardTracker = await ctx.factory.getDeployedContract<ReferralRewardTracker>("ReferralRewardTracker")
      const dptpFuturesGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>("DptpFuturesGateway");
      console.log(`Starting set counter party for referral storage`);
      await ctx.factory.waitTx(
          referralStorage.setCounterParty(referralRewardTracker.address,true),
          "referralStorage.setCounterParty",
          true
      );

      console.log(`Starting set counter party for referral reward tracker`);
      await ctx.factory.waitTx(
          referralRewardTracker.setCounterParty(dptpFuturesGateway.address,true),
          "referralRewardTracker.setCounterParty",
          true
      );

      console.log(`Starting set referral reward tracker for dptp futures gateway`);
      await ctx.factory.waitTx(
          dptpFuturesGateway.setReferralRewardTracker(referralRewardTracker.address),
          "dptpFuturesGateway.setReferralRewardTracker",
          true
      );
    },
  }),
};

export default migrations;
