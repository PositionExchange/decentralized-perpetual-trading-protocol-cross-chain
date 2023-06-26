import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { SUBTASK_NAME } from "./common";

export const VAULT_SetFuturXGateway_Action = async (args: {
  ctx: MigrationContext;
  futurXGateway: string;
  logMsg?: string;
}) => {
  const contract = await args.ctx.factory.getVault();
  await args.ctx.factory.waitTx(
    contract.setFuturXGateway(args.futurXGateway),
    args.logMsg || SUBTASK_NAME.FV_SetFuturXGateway
  );
};


