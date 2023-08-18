import {MigrationContext, MigrationDefinition} from "../types";

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => ({
        "deploy fee strategy": async () => {
            // Deploy fee strategy contract
            const argsFeeStrategy = [
                1
            ];
            await ctx.factory.createFeeStrategy(argsFeeStrategy);
            const dptpGateway = await ctx.db.findAddressByKey("DptpFuturesGateway");
            // Deploy FeeRebateVoucher
            const argsDptpGateway = [
                dptpGateway
            ];

            await ctx.factory.createFeeRebateVoucher(argsDptpGateway);
            await ctx.factory.createFeeRebateVoucherStrategy(argsDptpGateway);
            // set handler for FeeRebateVoucher -> FeeRebateVoucherStrategy
            // set handler for FeeRebateVoucherStrategy -> FeeStrategy
            // set handler for FeeStrategy -> Vault, DptpFuturesGateway
            // setVoucherFeeRebateToken in contract FeeRebateVoucherStrategy
        },
    }),
};

export default migrations;