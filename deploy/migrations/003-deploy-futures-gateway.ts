import {MigrationContext, MigrationDefinition} from "../types";
import {ContractWrapperFactory} from "../ContractWrapperFactory";
import {BigNumber} from "ethers";


const migrations: MigrationDefinition = {
    getTasks: (context: MigrationContext) => ({
        'deploy futures gateway': async () => {
            /**
             * Currently no param
             */
            // TODO config posi cross chain gateway address
            const futuresAdapterAddress = await context.db.findAddressByKey('FuturesAdapter');
            const insuranceFundAddress = await context.db.findAddressByKey('InsuranceFund');
            if (context.stage == "production") {
                await context.factory.createFuturesGateway({
                    futuresAdapter: futuresAdapterAddress,
                    posiCrosschainGatewayAddress: "0xa47a0fbd2f7b5c916496b1c1712e5dfb0839fe4f",
                    posiChainId: 900000,
                    insuranceFund: insuranceFundAddress,
                })
            } else if (context.stage == "okex_main") {
                await context.factory.createFuturesGateway({
                    futuresAdapter: futuresAdapterAddress,
                    posiCrosschainGatewayAddress: "0xa47a0fbd2f7b5c916496b1c1712e5dfb0839fe4f",
                    posiChainId: 900000,
                    insuranceFund: insuranceFundAddress,
                })
            } else if (context.stage == "test") {
                await context.factory.createFuturesGateway({
                    futuresAdapter: futuresAdapterAddress,
                    posiCrosschainGatewayAddress: "0xe79e86f27fde55cab31a4b4e9a615fd225613a13",
                    posiChainId: 910000,
                    insuranceFund: insuranceFundAddress,
                })
            } else {
                await context.factory.createFuturesGateway({
                    futuresAdapter: futuresAdapterAddress,
                    posiCrosschainGatewayAddress: "0xa978398879e248e61df480ead35636631d109174",
                    posiChainId: 920000,
                    insuranceFund: insuranceFundAddress,
                })
            }

        }
    })
}


export default migrations;
