import { run } from "hardhat";
import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
  FuturesAdapter,
  FuturXGatewayStorage,
  GatewayUtils,
  ReferralRewardTracker,
  WETH,
} from "../../typeChain";
import { SUBTASK_NAME } from "../tasks/common";
import {ARB_REFUNDERS, ARB_RELAYERS} from "../config_production";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy dptp futures gateway": async () => {
      const chainId = ctx.hre.network.config.chainId || 0;
      // TODO: Update pscCrossChainGateway by config mapping
      const pscId = chainId == 42161 ? 900000 : 910000;
      const weth =
        chainId == 42161
          ? "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"
          : await ctx.factory.db.findAddressByKey("WETH");
      const pscCrossChainGW = 41261
        ? "0x4b1573bc33a5d556C050D6F674B0924991ef0cdC"
        : "0x3230a2d25c81264F4e1A873729B53c62551Da792";

      const vault = await ctx.factory.db.findAddressByKey("Vault");

      const futuresAdapter = await ctx.factory.db.findAddressByKey(
        "FuturesAdapter"
      );
      const gatewayUtils = await ctx.factory.db.findAddressByKey(
        "GatewayUtils"
      );
      const futurXGatewayStorage = await ctx.factory.db.findAddressByKey(
        "FuturXGatewayStorage"
      );

      await ctx.factory.createDptpFuturesGateway({
        pcsId: pscId,
        pscCrossChainGateway: pscCrossChainGW,
        futuresAdapter: futuresAdapter,
        vault: vault,
        weth: weth,
        gatewayUtils: gatewayUtils,
        futurXGatewayStorage: futurXGatewayStorage,
        executionFee: 0,
      });

      // Create governance logic
      await ctx.factory.createFuturXGatewayGovernanceLogic();
    },

    "deploy tpsl gateway": async () => {
      await ctx.factory.createTPSLGateway();
    },

    "PROD config relayer whitelist": async () => {
      for (const relayer of ARB_RELAYERS) {
        await run(SUBTASK_NAME.FA_UpdateRelayerStatus, {
          ctx: ctx,
          relayer: relayer,
          status: true,
        });
      }
    },

    "PROD config refunder whitelist": async () => {
      for (const refunder of ARB_REFUNDERS) {
        await run(SUBTASK_NAME.FGW_SetPositionKeeper, {
          ctx: ctx,
          positionKeeper: refunder,
          status: true,
        });
      }
    },

    "re-config after deploy new gov": async () => {
      const gov = await ctx.db.findAddressByKey("DptpFuturesGatewayGovernance");
      await run(SUBTASK_NAME.FGW_SetGovernanceLogic, {
        ctx: ctx,
        gov: gov,
      });
    },

    "re-config after deploy new gateway": async () => {
      const managerBTC = "0x846d142804AF172c9a7Da38D82f26607C3EA2347";
      const managerETH = "0xf7A8a8971fCC59ca120Cd28F5079F09da29115cA";
      const managerLINK = "0x19e6C8AB4b17c6e022D4c0EA8ac3f3FcBf4E91A7";

      const wbtc = await ctx.factory.db.findAddressByKey("BTC");
      const weth = await ctx.factory.db.findAddressByKey("WETH");
      const link = await ctx.factory.db.findAddressByKey("LINK");

      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");

      await run(SUBTASK_NAME.FGW_SetCoreManager, {
        ctx: ctx,
        indexToken: wbtc,
        positionManager: managerBTC,
      });
      await run(SUBTASK_NAME.FGW_SetCoreManager, {
        ctx: ctx,
        indexToken: weth,
        positionManager: managerETH,
      });
      await run(SUBTASK_NAME.FGW_SetCoreManager, {
        ctx: ctx,
        indexToken: link,
        positionManager: managerLINK,
      });

      await run(SUBTASK_NAME.FGW_SetPositionKeeper, {
        ctx: ctx,
        positionKeeper: await ctx.db.findAddressByKey("FuturesAdapter"),
        status: true,
      });

      await run(SUBTASK_NAME.FGW_SetReferralRewardTracker, {
        ctx,
        referralRewardTracker: await ctx.db.findAddressByKey(
          "ReferralRewardTracker"
        ),
      });

      await run(SUBTASK_NAME.FGWS_SetFuturXGateway, {
        ctx,
        futurXGateway,
      });

      await run(SUBTASK_NAME.FV_SetFuturXGateway, {
        ctx,
        futurXGateway,
      });

      await run(SUBTASK_NAME.FGWU_SetFuturXGateway, {
        ctx,
        futurXGateway,
      });
    },
  }),
};

export default migrations;
