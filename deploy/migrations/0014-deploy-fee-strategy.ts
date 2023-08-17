import {MigrationContext, MigrationDefinition} from "../types";

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => ({
        "deploy fee strategy": async () => {
            // Deploy fee strategy contract
            const argsFeeStrategy = [
                1
            ];
            await ctx.factory.createFeeStrategy(argsFeeStrategy);
            const feeStrategy = await ctx.db.findAddressByKey("FeeStrategy");
            // Deploy FeeRebateVoucher
            const argsFeeRebateVoucher = [
                feeStrategy
            ];

            await ctx.factory.createFeeRebateVoucher(argsFeeRebateVoucher);
            await ctx.factory.createFeeRebateVoucherStrategy(argsFeeRebateVoucher);

        },
        // "upgrade vault" -> setFeeStrategy
        // "upgrade governance storage"
    }),
};

export default migrations;