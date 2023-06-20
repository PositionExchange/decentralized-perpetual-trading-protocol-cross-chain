import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, FuturXGatewayStorage } from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => ({
    "deploy futurx gateway storage": async () => {
      const futurXGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
      await ctx.factory.createFuturXGatewayStorage(futurXGateway);
    },

    "re-config after deploy futurx gateway storage": async () => {
      const futurXGateway =
        await ctx.factory.getDeployedContract<DptpFuturesGateway>(
          "DptpFuturesGateway"
        );
      const futurXGatewayStorage = await ctx.db.findAddressByKey(
        "FuturXGatewayStorage"
      );

      let tx: Promise<ContractTransaction>;

      const data = encodeDelegateCall(
        ["function setFuturXGatewayStorage(address _address)"],
        "setFuturXGatewayStorage",
        [futurXGatewayStorage]
      );
      tx = futurXGateway.executeGovFunction(data);
      await ctx.factory.waitTx(tx, "futurXGateway.setFuturXGatewayStorage");
    },
  }),
};

export default migrations;
