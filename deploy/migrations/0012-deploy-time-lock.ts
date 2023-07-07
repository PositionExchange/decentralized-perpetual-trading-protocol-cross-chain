import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, FuturXGatewayStorage } from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";
import { ARB_POSI_MAX_CAP, ARB_POSI_MINTER_ADDRESS } from "../../constants";
import { Token } from "../shared/types";
import { run } from "hardhat";
import { SUBTASK_NAME } from "../tasks/common";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({

    "deploy time lock testnet": async () => {

      const lpManager = await ctx.db.findAddressByKey("LpManager");
      const rewardRouter = await ctx.db.findAddressByKey("RewardRouter");
      const args = [
        '0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F',
        432000,
        '0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F',
        '0x9AC215Dcbd4447cE0aa830Ed17f3d99997a10F5F',
        lpManager,
        rewardRouter,
        0,
        10,
        40
      ]
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
      await ctx.factory.createTimeLock([futurXGateway]);
    },

    "deploy time mainnet": async () => {

      const lpManager = await ctx.db.findAddressByKey("LpManager");
      const rewardRouter = await ctx.db.findAddressByKey("RewardRouter");

      const args = [
          '0x0F92f378b9D2CbC1AED0D8F3Fbb9daA46f400e0b',
          432000,
          '0x0F92f378b9D2CbC1AED0D8F3Fbb9daA46f400e0b',
          '0x0F92f378b9D2CbC1AED0D8F3Fbb9daA46f400e0b',
          lpManager,
          rewardRouter,
          0,
          10,
          40
      ]
      await ctx.factory.createTimeLock(args);
    },

  }),
};

export default migrations;
