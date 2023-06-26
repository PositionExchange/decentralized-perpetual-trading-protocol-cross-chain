import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { SUBTASK_NAME } from "./common";

export const FGWS_SetFuturXGateway_Action = async (args: {
  ctx: MigrationContext;
  futurXGateway: string;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getFuturXGatewayStorage();
  await args.ctx.factory.waitTx(
    contract.setFuturXGateway(args.futurXGateway),
    args.logMsg || SUBTASK_NAME.FGWS_SetFuturXGateway
  );
};

export const FGWS_SetHandler_Action = async (args: {
  ctx: MigrationContext;
  handler: string;
  status: boolean;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getFuturXGatewayStorage();
  await args.ctx.factory.waitTx(
      contract.setHandler(args.handler, args.status),
      args.logMsg || SUBTASK_NAME.FGWS_SetHandler
  );
};