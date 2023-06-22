import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, FuturXGatewayStorage } from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";
import {ARB_POSI_MAX_CAP, ARB_POSI_MINTER_ADDRESS} from "../../constants";
import {Token} from "../shared/types";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx gateway storage": async () => {
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
      await ctx.factory.createFuturXGatewayStorage(futurXGateway);
    },

    "re-config after deploy futurx gateway storage": async () => {
      const futurXGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );
      const futurXGatewayStorage = await ctx.db.findAddressByKey(
        "FuturXGatewayStorage"
      );

      let tx: Promise<ContractTransaction>;

      const data = encodeDelegateCall(
        ["function setFuturXGatewayStorage(address _address)"],
        "setFuturXGatewayStorage",
        [futurXGatewayStorage]
      );
      tx = futurXGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXGatewayStorage");
    },

    "verifyaaaaaa": async () => {
      const vestingDuration = 365 * 24 * 60 * 60
      const esPosi = await ctx.db.findAddressByKey("EsPOSI")
      const stakedPosiTracker = await ctx.db.findAddressByKey("StakedPosiTracker")
      const feePosiTracker = await ctx.db.findAddressByKey("FeePosiTracker")
      const posi = await ctx.db.findAddressByKey("POSI")
      const nativeToken = ctx.factory.contractConfig.getStageConfig<typeof Token>('native_token')

      const contracts = {
        "StakedPosiDistributor": [esPosi, stakedPosiTracker],
        "StakedPosiTracker": ["Staked POSI", "sPOSI"],
        "FeePosiTracker": ["Staked + Bonus + Fee POSI", "sbfPOSI"],
        "BonusPosiTracker": ["Staked + Bonus POSI", "sbPOSI"],
        "FeePosiDistributor": [nativeToken.address, feePosiTracker],
        "BnPOSI": ["Bonus POSI", "bnPOSI", 0],
        "FeePlpTracker": ["Fee PLP", "fPLP"],
        "VestedPOSI": [
          "Vested POSI", // _name
          "vPOSI", // _symbol
          vestingDuration, // _vestingDuration
          esPosi, // _esToken
          feePosiTracker, // _pairToken
          posi, // _claimableToken
          stakedPosiTracker, // _rewardTracker
        ],
        "POSI": [ARB_POSI_MINTER_ADDRESS, ARB_POSI_MAX_CAP],
      }

      for (const [name, args] of Object.entries(contracts)) {
        const address = await ctx.db.findAddressByKey(name)
        await ctx.factory.verify2(address, args)
      }
    },
  }),
};

export default migrations;
