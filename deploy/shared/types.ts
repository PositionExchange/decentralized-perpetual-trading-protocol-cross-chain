
export type ContractAddress = string;

export class Token<T> {
  constructor(
    public readonly chainId: number,
    public name: string,
    public symbol: string,
    public decimals: number,
    public address: ContractAddress, 
    public extraConfig?: T
  ) {}

  toJson() {
    return {
      name: this.name,
      symbol: this.symbol,
      decimals: this.decimals,
      address: this.address,
    }
  }
}

export interface IVaultTokenConfig {
  mintProfitBps: number
  tokenWeight: number
  maxUsdpAmount: number
  isStableToken: boolean
  isShortable: boolean
}

export interface IPriceFeedConfig {
  chainLinkPriceFeed: ContractAddress
  priceFeedDecimals: number
  spreadBasisPoints: number
  isStrictStable: boolean
}


export interface IExtraTokenConfig {
  vaultTokenConfig: IVaultTokenConfig
  priceFeedConfig: IPriceFeedConfig
}

type ChainConfig<T> = {
  [chainId: number]: T
}

export class MultiChainToken<T> {
  constructor(
    public name: string,
    public symbol: string,
    public decimals: number | ChainConfig<number>,
    public addresses: ChainConfig<ContractAddress>,
    public extraConfig?: ChainConfig<T>
  ) {}

  public forChain(chainId: number): Token<T> {
    if(!this.addresses[chainId]) {
      throw new Error(`No address for chain ${chainId}`)
    }
    const decimals = typeof this.decimals === 'number' ? this.decimals : this.decimals[chainId]
    return new Token<T>(
      chainId,
      this.name,
      this.symbol,
      decimals,
      this.addresses[chainId],
      this.extraConfig[chainId]
    )
  }
}
