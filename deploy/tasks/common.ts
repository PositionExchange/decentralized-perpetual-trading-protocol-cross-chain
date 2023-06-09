import { ArgumentType } from "hardhat/src/types/runtime";

export const any: ArgumentType<any> = {
  name: "any",
  validate(_argName: string, _argumentValue: any) {},
};

export const SUBTASK_NAME = {
  // FuturX Gateway Storage
  FGWS_SetFuturXGateway: "futurXGatewayStorage.setFuturXGateway",
  FGWS_SetHandler: "futurXGatewayStorage.setHandler",

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
  FGW_SetVault: "futurXGateway.setVault",
  FGW_SetFuturXVoucher: "futurXGateway.setFuturXVoucher",

  // FuturX Adapter
  FA_UpdateRelayerStatus: "FA_UpdateRelayerStatus",

  // Vault
  VAULT_SetFuturXGateway: "VAULT_SetFuturXGateway",

  // ReferralRewardTracker
  RRT_SetCounterParty: "RRT_SetCounterParty",
};