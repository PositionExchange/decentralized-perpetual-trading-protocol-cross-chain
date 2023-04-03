import { BNB, BUSD, WETH, DAI, USDT, BTC, POSI } from "./tokens"
import { Token } from "./types"

export interface StageConfig<K extends string,T> {
  [stage: string]: {
    [networkId: number]: {
      [name in K]: T
    }
  }
}

export type AvailableStageConfig = 'whitelist' | 'native_token'

export const stageConfig: StageConfig<AvailableStageConfig,any> = {
  'production': {},
  'test': {
    97: {
      whitelist: [
        BNB.forChain(97),
        BUSD.forChain(97),
        DAI.forChain(97),
        USDT.forChain(97),
        WETH.forChain(97),
        BTC.forChain(97),
        // POSI.forChain(97),
      ],
      native_token: BNB.forChain(97)
    }
  }
}

// if the contract doesn't exist, it will create a mock address
export const addresses: StageConfig<string, string> = {
  'production': {
    56: {
      BUSD: '0xe9e7cea3dedca5984780bafc599bd69add087d56',
    }
  },
  'test': {
    97: {

    }
  }
}
