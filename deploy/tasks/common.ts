import { ArgumentType } from "hardhat/src/types/runtime";

export const any: ArgumentType<any> = {
  name: "any",
  validate(_argName: string, _argumentValue: any) {},
};

export const TASK_NAME = {
  FGWS_SetFuturXGateway: "futurXGatewayStorage.setFuturXGateway",

  FGWU_SetFuturXGateway: "futurXGatewayUtils.setFuturXGateway",

  FV_SetFuturXGateway: "futurXVoucher.setFuturXGateway",

  FGW_SetCoreManager: "futurXGateway.setCoreManager",
  FGW_SetPositionKeeper: "futurXGateway.setPositionKeeper",
  FGW_SetReferralRewardTracker: "futurXGateway.setReferralRewardTracker",
  FGW_SetPscCrossChain: "futurXGateway.setPosiChainCrosschainGatewayContract",
};
