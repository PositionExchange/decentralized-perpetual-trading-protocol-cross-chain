import { subtask } from "hardhat/config";
import { any, SUBTASK_NAME } from "./common";
import { MigrationContext } from "../types";
import { FGWS_SetFuturXGateway_Action } from "./FuturXGatewayStorageTasks";
import { FV_SetFuturXGateway_Action } from "./FuturXVoucherTasks";
import { FGWU_SetFuturXGateway_Action } from "./FuturXGatewayUtilsTasks";
import {
  FGW_SetCoreManager_Action, FGW_SetGovernanceLogic_Action,
  FGW_SetPositionKeeper_Action,
  FGW_SetPscCrossChain_Action,
  FGW_SetReferralRewardTracker_Action,
} from "./FuturXGatewayTasks";
import { FA_UpdateRelayerStatus_Action } from "./FuturXAdapterTasks";
import {VAULT_SetFuturXGateway_Action} from "./VaultTasks";

subtask(SUBTASK_NAME.FGW_SetCoreManager)
  .setAction(FGW_SetCoreManager_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("indexToken")
  .addParam("positionManager")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGW_SetPositionKeeper)
  .setAction(FGW_SetPositionKeeper_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("positionKeeper")
  .addParam<boolean>("status", "", false, any)
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGW_SetReferralRewardTracker)
  .setAction(FGW_SetReferralRewardTracker_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("referralRewardTracker")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGW_SetPscCrossChain)
  .setAction(FGW_SetPscCrossChain_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("pscCrossChain")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGW_SetGovernanceLogic)
  .setAction(FGW_SetGovernanceLogic_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("gov")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGWU_SetFuturXGateway)
  .setAction(FGWU_SetFuturXGateway_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("futurXGateway")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FGWS_SetFuturXGateway)
  .setAction(FGWS_SetFuturXGateway_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("futurXGateway")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FV_SetFuturXGateway)
  .setAction(FV_SetFuturXGateway_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("futurXGateway")
  .addOptionalParam("logMsg");

subtask(SUBTASK_NAME.FA_UpdateRelayerStatus)
  .setAction(FA_UpdateRelayerStatus_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("relayer")
  .addParam<boolean>("status", "", false, any)
  .addOptionalParam("logMsg");


subtask(SUBTASK_NAME.VAULT_SetFuturXGateway)
  .setAction(VAULT_SetFuturXGateway_Action)
  .addParam<MigrationContext>("ctx", "MigrationContext", null, any)
  .addParam("futurXGateway")
  .addOptionalParam("logMsg");
