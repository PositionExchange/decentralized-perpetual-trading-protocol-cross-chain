import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { SUBTASK_NAME } from "./common";

export const RRT_SetCounterParty_Action = async (args: {
  ctx: MigrationContext;
  counterParty: string;
  status: boolean;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getReferralRewardTracker();
  await args.ctx.factory.waitTx(
    contract.setCounterParty(args.counterParty, args.status),
    args.logMsg || SUBTASK_NAME.RRT_SetCounterParty
  );
};
