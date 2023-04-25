import {MigrationContext, MigrationDefinition} from "../types";
import {ContractWrapperFactory} from "../ContractWrapperFactory";


const migrations: MigrationDefinition = {
    getTasks: (context: MigrationContext) => ({
        'deploy futures adapter': async () => {
            /**
             * Currently no param
             */
            if (context.stage == "production") {
                await context.factory.createFuturesAdapter({
                    myBlockchainId: 56,
                    timeHorizon: 86400
                })
            } else if (context.stage == "okex_main") {
                await context.factory.createFuturesAdapter({
                    myBlockchainId: 66,
                    timeHorizon: 86400
                })
            } else if (context.stage == "test") {
                await context.factory.createFuturesAdapter({
                    myBlockchainId: 97,
                    timeHorizon: 86400
                })
            } else if (context.stage == "arbitrumGoerli") {
                await context.factory.createFuturesAdapter({
                    myBlockchainId: 421613,
                    timeHorizon: 86400
                })
            } else {
                await context.factory.createFuturesAdapter({
                    myBlockchainId: 930000,
                    timeHorizon: 86400
                })
            }
            // await context.factory.createFuturesAdapter({
            //     myBlockchainId: 65,
            //     timeHorizon: 86400
            // })
        }
    })
}


export default migrations;
