import "@nomiclabs/hardhat-ethers";
import { encodeDelegateCall } from "../shared/utils";
import { MigrationContext } from "../types";
import { TASK_NAME } from "./common";

const GOV_ABI = [
  "function setCoreManager(address _token, address _manager)",
  "function setPositionKeeper(address _address)",
  "function setReferralRewardTracker(address _address)",
  "function setPosiChainCrosschainGatewayContract(address _address)",
];

const executeGovFunc = async (
  ctx: MigrationContext,
  funcName: string,
  funcValue: any[],
  logMsg: string
) => {
  const futurXGateway = await ctx.factory.getFuturXGateway();
  const data = encodeDelegateCall(GOV_ABI, funcName, funcValue);
  await ctx.factory.waitTx(futurXGateway.executeGovFunction(data), logMsg);
};

export const FGW_SetCoreManager_Action = async (args: {
  ctx: MigrationContext;
  indexToken: string;
  positionManager: string;
  logMsg?: string;
}) => {
  await executeGovFunc(
    args.ctx,
    "setCoreManager",
    [args.indexToken, args.positionManager],
    args.logMsg || TASK_NAME.FGW_SetCoreManager
  );
};

export const FGW_SetPositionKeeper_Action = async (args: {
  ctx: MigrationContext;
  positionKeeper: string;
  logMsg?: string;
}) => {
  await executeGovFunc(
    args.ctx,
    "setPositionKeeper",
    [args.positionKeeper],
    args.logMsg || TASK_NAME.FGW_SetPositionKeeper
  );
};

export const FGW_SetReferralRewardTracker_Action = async (args: {
  ctx: MigrationContext;
  referralRewardTracker: string;
  logMsg?: string;
}) => {
  await executeGovFunc(
    args.ctx,
    "setReferralRewardTracker",
    [args.referralRewardTracker],
    args.logMsg || TASK_NAME.FGW_SetReferralRewardTracker
  );
};

export const FGW_SetPscCrossChain_Action = async (args: {
  ctx: MigrationContext;
  pscCrossChain: string;
  logMsg?: string;
}) => {
  await executeGovFunc(
    args.ctx,
    "setPosiChainCrosschainGatewayContract",
    [args.pscCrossChain],
    args.logMsg || TASK_NAME.FGW_SetPscCrossChain
  );
};
