import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { TASK_NAME } from "./common";

export const FA_UpdateRelayerStatus_Action = async (args: {
  ctx: MigrationContext;
  relayer: string;
  status: boolean;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getFuturesAdapter();
  const tx = contract.updateRelayerStatus(args.relayer, args.status);

  await args.ctx.factory.waitTx(
    tx,
    args.logMsg || TASK_NAME.FA_UpdateRelayerStatus
  );
};
