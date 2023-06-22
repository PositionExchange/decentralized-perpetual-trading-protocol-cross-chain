import { ArgumentType } from "hardhat/src/types/runtime";

export const any: ArgumentType<any> = {
  name: "any",
  validate(_argName: string, _argumentValue: any) {},
};

export const SUBTASK_NAME = {
  // FuturX Gateway Storage
  FGWS_SetFuturXGateway: "futurXGatewayStorage.setFuturXGateway",

  // FuturX Gateway Utils
  FGWU_SetFuturXGateway: "futurXGatewayUtils.setFuturXGateway",

  // FuturX Voucher
  FV_SetFuturXGateway: "futurXVoucher.setFuturXGateway",

  // FuturX Gateway
  FGW_SetCoreManager: "futurXGateway.setCoreManager",
  FGW_SetPositionKeeper: "futurXGateway.setPositionKeeper",
  FGW_SetReferralRewardTracker: "futurXGateway.setReferralRewardTracker",
  FGW_SetPscCrossChain: "futurXGateway.setPosiChainCrosschainGatewayContract",
  FGW_SetGovernanceLogic: "futurXGateway.setGovernanceLogic",

  // FuturX Adapter
  FA_UpdateRelayerStatus: "FA_UpdateRelayerStatus",
};