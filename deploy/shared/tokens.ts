import { IExtraTokenConfig, MultiChainToken } from "./types";

/*
BNB Testnet
BNB / USD: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
BUSD / USD: 0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa
USDT / USD: 0xEca2605f0BCF2BA5966372C99837b1F182d3D620
ETH / USD: 0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7
BTC / USD: 0x5741306c21795FdCBb9b265Ea0255F499DFe515C
DAI / USD: 0xE4eE17114774713d2De0eC0f035d4F7665fc025D
*/
const priceFeedBNBTestNet = {
  'BNB_USD': '0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526',
  'BUSD_USD': '0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa',
  'USDT_USD': '0xEca2605f0BCF2BA5966372C99837b1F182d3D620',
  'ETH_USD': '0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7',
  'BTC_USD': '0x5741306c21795FdCBb9b265Ea0255F499DFe515C',
  'DAI_USD': '0xE4eE17114774713d2De0eC0f035d4F7665fc025D'
};
export const BNB = new MultiChainToken<IExtraTokenConfig>('BNB', 'BNB', 18, 
{
  56: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
  97: '0x1424Cd8e3B4c970ef52F88e8AccFbc4242BDc78b'
}, 
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['BNB_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  }
})

export const BUSD = new MultiChainToken<IExtraTokenConfig>('BUSD', 'BUSD', 18, {
  56: '0xe9e7cea3dedca5984780bafc599bd69add087d56',
  97: '0xb9838B8EeD90731e44733881a04D275Eb4064288'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['BUSD_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  }
}
)

export const USDT = new MultiChainToken<IExtraTokenConfig>('USDT', 'USDT', 18, {
  56: '',
  97: '0x542E4676238562b518B968a1d03626d544a7BCA2'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['USDT_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  }
}
)

// config for DAI, WETH, BTC, POSI
export const DAI = new MultiChainToken<IExtraTokenConfig>('DAI', 'DAI', 18, {
  56: '0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3',
  97: '0xB202545C693631eEeBC83E600c74cFf4EE54F39c'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['DAI_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  }
})


export const WETH = new MultiChainToken<IExtraTokenConfig>('WETH', 'WETH', 18, {
  56: '0x2170ed0880ac9a755fd29b2688956bd959f933f8',
  97: '0x4D906559B2cEbBe063757ab76c5620C2149e4b0D'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['ETH_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  }
}
)

export const BTC = new MultiChainToken<IExtraTokenConfig>('BTC', 'BTC', 8, {
  56: '0x7130d2a12b9bcbfae4f2634d864a1ee1ce3ead9c',
  97: '0xc4900937c3222CA28Cd4b300Eb2575ee0868540F'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedBNBTestNet['BTC_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  }
}
)

export const POSI = new MultiChainToken<IExtraTokenConfig>('POSI', 'POSI', 18, {
  56: '0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82',
  97: '0x2c7e96Ad431Bf93bD316b9a67C164dC35FD18e7c'
},
{
  97: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 10,
      maxUsdpAmount: 10 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: "",
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  }
}
)

