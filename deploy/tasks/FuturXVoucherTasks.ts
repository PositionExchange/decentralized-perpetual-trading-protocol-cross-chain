import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { TASK_NAME } from "./common";

export const FV_SetFuturXGateway_Action = async (args: {
  ctx: MigrationContext;
  futurXGateway: string;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getFuturXVoucher();
  await args.ctx.factory.waitTx(
    contract.setFuturXGateway(args.futurXGateway),
    args.logMsg || TASK_NAME.FV_SetFuturXGateway
  );
};


