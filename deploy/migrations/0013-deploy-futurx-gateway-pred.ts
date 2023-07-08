import { MigrationContext, MigrationDefinition } from "../types";
import { DptpFuturesGateway, FuturXGatewayStorage } from "../../typeChain";
import { ContractTransaction } from "ethers";
import { encodeDelegateCall } from "../shared/utils";
import { ARB_POSI_MAX_CAP, ARB_POSI_MINTER_ADDRESS } from "../../constants";
import { Token } from "../shared/types";
import { run } from "hardhat";
import { SUBTASK_NAME } from "../tasks/common";

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => ({

        "deploy gateway pre-data": async () => {

            const dptpFuturesGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
            const vault = await ctx.db.findAddressByKey("Vault");

            const gatewayUtils = await ctx.db.findAddressByKey("GatewayUtils");
            const futurXGatewayStorage = await ctx.db.findAddressByKey("FuturXGatewayStorage");

            const args = [
                dptpFuturesGateway,
                vault,
                gatewayUtils,
                futurXGatewayStorage
            ];
            await ctx.factory.createGatewayPreData(args);
        },


    }),
};

export default migrations;
