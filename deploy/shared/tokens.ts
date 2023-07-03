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
const priceFeedARBTestNet = {
  'BTC_USD': '0x6550bc2301936011c1334555e62A87705A81C12C',
  'ETH_USD': '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08',
  'LINK_USD': '0xd28Ba6CA3bB72bF371b80a2a0a33cBcf9073C954',
  'USDT_USD': '0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E',
  'DAI_USD': '0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1',
  'USDC_USD': '0x1692Bdd32F31b831caAc1b0c9fAF68613682813b'
};
const priceFeedArbOne = {
  'BTC_USD': '0x6ce185860a4963106506c203335a2910413708e9',
  'ETH_USD': '0x639fe6ab55c921f74e7fac1ee960c0b6293ba612',
  'LINK_USD': '0x86e53cf1b870786351da77a57575e79cb55812cb',
  'USDC_USD': '0x50834f3163758fcc1df9973b6e91f0f0f0434ad3',
  'USDT_USD': '0x3f3f5df88dc9f13eac63df89ec16ef6e7e25dde7',
  'DAI_USD': '0xc5c8e77b397e531b8ec06bfb0048328b30e9ecfb'
};

export const BNB = new MultiChainToken<IExtraTokenConfig>('BNB', 'BNB', 18,
{
  56: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
  97: '0x1424Cd8e3B4c970ef52F88e8AccFbc4242BDc78b',
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
  97: '0xb9838B8EeD90731e44733881a04D275Eb4064288',
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

export const USDT = new MultiChainToken<IExtraTokenConfig>('USDT', 'USDT', 6, {
  56: '',
  97: '0x542E4676238562b518B968a1d03626d544a7BCA2',
  421613: '0x38193a1c61B2B44446289265580F73746F5BB5AE',
  42161: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9'
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
  },
  421613: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedARBTestNet['USDT_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  },
  42161: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedArbOne['USDT_USD'],
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
  97: '0xB202545C693631eEeBC83E600c74cFf4EE54F39c',
  421613: '0xeB38ba492650c7ea62047E0e879C6a5F6c3e9D8C',
  42161: '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1',
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
  },
  421613: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedARBTestNet['DAI_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  },
  42161: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: true,
      isShortable: false
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedArbOne['DAI_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: true
    }
  }
})


export const WETH = new MultiChainToken<IExtraTokenConfig>('WETH', 'WETH', 18, {
  56: '0x2170ed0880ac9a755fd29b2688956bd959f933f8',
  97: '0x4D906559B2cEbBe063757ab76c5620C2149e4b0D',
  421613: '0x471385598B0Bdb63C89082F4166C0577C6C0263a',
  42161: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1',
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
  },
  421613: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedARBTestNet['ETH_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  },
  42161: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedArbOne['ETH_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  }
}
)

export const BTC = new MultiChainToken<IExtraTokenConfig>('BTC', 'BTC', 8, {
  56: '0x7130d2a12b9bcbfae4f2634d864a1ee1ce3ead9c',
  97: '0xc4900937c3222CA28Cd4b300Eb2575ee0868540F',
  421613: '0xA8cc0c527a271c7D196f12c23a65DbFB58C033F5',
  42161: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
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
  },
  421613: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedARBTestNet['BTC_USD'],
      priceFeedDecimals: 8,
      spreadBasisPoints: 10,
      isStrictStable: false
    }
  },
  42161: {
    vaultTokenConfig: {
      mintProfitBps: 0,
      tokenWeight: 100,
      maxUsdpAmount: 100 * 1e6,
      isStableToken: false,
      isShortable: true
    },
    priceFeedConfig: {
      chainLinkPriceFeed: priceFeedArbOne['BTC_USD'],
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

export const LINK = new MultiChainToken<IExtraTokenConfig>('LINK', 'LINK', 18, {
      421613: '0x74c0348CC6027b0c60C27c2c6b8Cf32C5510b569',
      42161: '0xf97f4df75117a78c1a5a0dbb814af92458539fb4'
    },
    {
      421613: {
        vaultTokenConfig: {
          mintProfitBps: 0,
          tokenWeight: 100,
          maxUsdpAmount: 100 * 1e6,
          isStableToken: false,
          isShortable: true
        },
        priceFeedConfig: {
          chainLinkPriceFeed: priceFeedARBTestNet['LINK_USD'],
          priceFeedDecimals: 8,
          spreadBasisPoints: 10,
          isStrictStable: false
        }
      },
      42161: {
        vaultTokenConfig: {
          mintProfitBps: 0,
          tokenWeight: 100,
          maxUsdpAmount: 100 * 1e6,
          isStableToken: false,
          isShortable: true
        },
        priceFeedConfig: {
          chainLinkPriceFeed: priceFeedArbOne['LINK_USD'],
          priceFeedDecimals: 8,
          spreadBasisPoints: 10,
          isStrictStable: false
        }
      }
    }
)

export const USDC = new MultiChainToken<IExtraTokenConfig>('USDC', 'USDC', 6, {
      421613: '0x42C2Bd247fbe4804C52999f33105Ad705Dee3bC5',
      42161: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8'
    },
    {
      421613: {
        vaultTokenConfig: {
          mintProfitBps: 0,
          tokenWeight: 100,
          maxUsdpAmount: 100 * 1e6,
          isStableToken: true,
          isShortable: false
        },
        priceFeedConfig: {
          chainLinkPriceFeed: priceFeedARBTestNet['USDC_USD'],
          priceFeedDecimals: 8,
          spreadBasisPoints: 10,
          isStrictStable: true
        }
      },
      42161: {
        vaultTokenConfig: {
          mintProfitBps: 0,
          tokenWeight: 100,
          maxUsdpAmount: 100 * 1e6,
          isStableToken: true,
          isShortable: false
        },
        priceFeedConfig: {
          chainLinkPriceFeed: priceFeedArbOne['USDC_USD'],
          priceFeedDecimals: 8,
          spreadBasisPoints: 10,
          isStrictStable: true
        }
      }
    }
)