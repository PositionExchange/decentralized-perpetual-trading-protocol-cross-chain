import "@nomiclabs/hardhat-ethers";
import { MigrationContext } from "../types";
import { SUBTASK_NAME } from "./common";

export const VAULT_SetFuturXGateway_Action = async (args: {
  ctx: MigrationContext;
  logMsg?: string;
}) => {
  const vault = await args.ctx.factory.getVault();
  const futurXGateway = await args.ctx.factory.getFuturXGateway();

  await args.ctx.factory.waitTx(
    vault.setFuturXGateway(futurXGateway.address),
    args.logMsg || SUBTASK_NAME.VAULT_SetFuturXGateway
  );
};


