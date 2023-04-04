import { MigrationContext, MigrationDefinition } from "../types";

const migrations: MigrationDefinition = {
  getTasks: (context: MigrationContext) => ({
    "deploy dptp futures gateway": async () => {
      await context.factory.createDptpFuturesGateway({
        pcsId: 910000,
        pscCrossChainGateway: '0xadf94555e5f2eae345692b8b39f062640e42b06f',
        futuresAdapter: '0xc00902879e622a234ddbc1c41d0614feed74a0ff',
        vault: '0xF55Fc8e91c0c893568dB750cD4a4eB2D953E80a5',
        weth: '0xae13d989dac2f0debff460ac112a837c89baa7cd',
        executionFee: 0,
      });
    },
  }),
};

export default migrations;
