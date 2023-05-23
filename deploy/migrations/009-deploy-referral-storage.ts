import { MigrationContext, MigrationDefinition } from "../types";
import {DptpFuturesGateway, ReferralRewardTracker, ReferralStorage, Vault} from "../../typeChain";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral storage": async () => {
      await ctx.factory.createReferralStorage();
      const referralStorage= await ctx.factory.getDeployedContract<ReferralStorage>("ReferralStorage");
      // TODO move to config
      await ctx.factory.waitTx(
          referralStorage.setTier(1,500,500),
          "referralStorage.setTier",
          true
      );
      await ctx.factory.waitTx(
          referralStorage.setTier(2,1000,1000),
          "referralStorage.setTier",
          true
      );
      await ctx.factory.waitTx(
          referralStorage.setTier(3,1500,1500),
          "referralStorage.setTier",
          true
      );
    },

    "deploy referral reward tracker": async () => {
      const referralStorage= await ctx.factory.db.findAddressByKey("ReferralStorage");
      const rewardToken = await ctx.factory.db.findAddressByKey("USDT");
      const tokenDecimal = 6;
      await ctx.factory.createReferralRewardTracker(
          {
            rewardToken,
            tokenDecimal,
            referralStorage
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
