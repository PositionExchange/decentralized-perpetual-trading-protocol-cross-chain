import "@nomiclabs/hardhat-ethers";
import { encodeDelegateCall } from "../shared/utils";
import { MigrationContext } from "../types";
import { SUBTASK_NAME } from "./common";

const GOV_ABI = [
  "function setCoreManager(address _token, address _manager)",
  "function setPositionKeeper(address _address, bool _status)",
  "function setReferralRewardTracker(address _address)",
  "function setPosiChainCrosschainGatewayContract(address _address)",
  "function setGovernanceLogic(address _newGovernanceLogic)",
  "function setVault(address _vault)",
  "function setFuturXVoucher(address _address)",
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
    args.logMsg || SUBTASK_NAME.FGW_SetCoreManager
  );
};

export const FGW_SetPositionKeeper_Action = async (args: {
  ctx: MigrationContext;
  positionKeeper: string;
  status: boolean;
  logMsg?: string;
}) => {
  await executeGovFunc(
    args.ctx,
    "setPositionKeeper",
    [args.positionKeeper, args.status],
    args.logMsg || SUBTASK_NAME.FGW_SetPositionKeeper
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
    args.logMsg || SUBTASK_NAME.FGW_SetReferralRewardTracker
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
    args.logMsg || SUBTASK_NAME.FGW_SetPscCrossChain
  );
};

export const FGW_SetGovernanceLogic_Action = async (args: {
  ctx: MigrationContext;
  logMsg?: string;
}) => {
  const futurXGateway = await args.ctx.factory.getFuturXGateway();
  const gov = await args.ctx.db.findAddressByKey(
    "DptpFuturesGatewayGovernance"
  );

  await args.ctx.factory.waitTx(
    futurXGateway.setGovernanceLogic(gov),
    args.logMsg || SUBTASK_NAME.FGW_SetGovernanceLogic
  );
};

export const FGW_SetVault_Action = async (args: {
  ctx: MigrationContext;
  logMsg?: string;
}) => {
  const vault = await args.ctx.factory.getVault();
  await executeGovFunc(
    args.ctx,
    "setVault",
    [vault.address],
    args.logMsg || SUBTASK_NAME.FGW_SetVault
  );
};

export const FGW_SetFuturXVoucher_Action = async (args: {
  ctx: MigrationContext;
  logMsg?: string;
}) => {
  const voucher = await args.ctx.factory.getFuturXVoucher();
  await executeGovFunc(
    args.ctx,
    "setFuturXVoucher",
    [voucher.address],
    args.logMsg || SUBTASK_NAME.FGW_SetFuturXVoucher
  );
};
