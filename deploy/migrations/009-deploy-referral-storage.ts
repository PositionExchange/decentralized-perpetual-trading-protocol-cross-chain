import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, ReferralRewardTracker } from "../../typeChain";
import {encodeDelegateCall} from "../shared/utils";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy referral reward tracker": async () => {
      const chainId = ctx.hre.network.config.chainId || 0;
      const rewardToken =
        chainId == 42161
          ? "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"
          : await ctx.factory.db.findAddressByKey("USDT");
      const tokenDecimal = 6;
      await ctx.factory.createReferralRewardTracker({
        rewardToken,
        tokenDecimal,
      });
    },

    "re-config after deploy referral reward tracker": async () => {
      const referralRewardTracker =
        await ctx.factory.getDeployedContract<ReferralRewardTracker>(
          "ReferralRewardTracker"
        );
      const dptpFuturesGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );

      // Set tiers
      // await ctx.factory.waitTx(
      //   referralRewardTracker.setTier(1, 500, 500),
      //   "referralStorage.setTier"
      // );
      // await ctx.factory.waitTx(
      //   referralRewardTracker.setTier(2, 1000, 1000),
      //   "referralStorage.setTier"
      // );
      // await ctx.factory.waitTx(
      //   referralRewardTracker.setTier(3, 1500, 1500),
      //   "referralStorage.setTier"
      // );
      //
      // // Set contract addresses
      // await ctx.factory.waitTx(
      //   referralRewardTracker.setCounterParty(dptpFuturesGateway.address, true),
      //   "referralRewardTracker.setCounterParty"
      // );

      const data = encodeDelegateCall(
          ["function setReferralRewardTracker(address _address)"],
          "setReferralRewardTracker",
          [referralRewardTracker.address]
      );
      await ctx.factory.waitTx(
        dptpFuturesGateway.executeGovFunction(data),
        "dptpFuturesGateway.setReferralRewardTracker"
      );
    },
  }),
};

export default migrations;
