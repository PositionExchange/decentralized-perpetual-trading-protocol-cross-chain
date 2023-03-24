import { ethers } from "hardhat"
import type * as ethersE from "ethers";
import {
  FactoryOptions
} from "@nomiclabs/hardhat-ethers/types";
import { MockToken, USDP, Vault } from "../../typeChain";
import { loadContractFixtures, loadMockTokenFixtures } from "./fixtures";
import { expect } from "chai";
import * as helpers from "@nomicfoundation/hardhat-network-helpers"


export async function deployContract<T>(name: string, args: any[] = [], options?: ethersE.Signer | FactoryOptions) {
  const contractFactory = await ethers.getContractFactory(name, options)
  return (await contractFactory.deploy(...args)) as unknown as T;
}

export function toChainlinkPrice(value: string | number) {
  return parseInt(`${Number(value) * Math.pow(10, 8)}`)
}

export function toPriceFeedPrice(value: string | number) {
  // return 30-8
  return ethers.utils.parseUnits(`${Number(value)}`, 30)
}

interface IPoolData{
    feeReserve: ethersE.BigNumber;
    usdpAmount: ethersE.BigNumber;
    poolAmount: ethersE.BigNumber;
    reservedAmount: ethersE.BigNumber;
}

export class VaultTracker {
  usdpBefore: ethersE.BigNumber;
  underlyingToken: MockToken;
  underlyingBalanceBefore: ethersE.BigNumber;
  poolDataBefore: IPoolData;
  cacheAddress2Name: {}
  isFirstTime = true
  tokenFixtures: {}

  constructor(protected vault: Vault, protected usdp: USDP, protected underlyingTokenAddress: string, protected user: string, protected config: {
    verbose?: boolean
  } = {
    verbose: true
  }) {
  }

  // @deprecated call init instead
  async beforePurchase(newUnderlyingTokenAddress?: string){
    return this.init({newUnderlyingTokenAddress, resetState: false})
  }

  async init({newUnderlyingTokenAddress, resetState}: {newUnderlyingTokenAddress?: string; resetState?: boolean} = {}) {
    if(this.isFirstTime || resetState){
      const tokenFixtures = await loadMockTokenFixtures()
      this.tokenFixtures = tokenFixtures
      const {usdp, address2Name} = tokenFixtures
      const {vault} = await loadContractFixtures()
      this.cacheAddress2Name = address2Name
      this.vault = vault
      this.usdp = usdp
      this.isFirstTime = false
      const tokenSymbol = this.cacheAddress2Name[this.underlyingTokenAddress]
      const tokenContract = tokenFixtures[tokenSymbol] || tokenFixtures[tokenSymbol.toLowerCase()]
      this.underlyingToken = tokenContract
    }
    if(newUnderlyingTokenAddress){
      this.underlyingTokenAddress = newUnderlyingTokenAddress
      const tokenSymbol = this.cacheAddress2Name[this.underlyingTokenAddress]
      const tokenContract = this.tokenFixtures[tokenSymbol] || this.tokenFixtures[tokenSymbol.toLowerCase()]
      this.underlyingToken = tokenContract
    }
    this.usdpBefore = await this.usdp.balanceOf(this.user)
    this.poolDataBefore = await this.getPoolData()
    if(this.underlyingToken){
        this.underlyingBalanceBefore = await this.underlyingToken.balanceOf(this.user)
      }
    this.printPoolData(this.poolDataBefore, 'before')
  }

  async expectAfter({
    usdpBalanceDiff,
    poolDataDiff,
    underlyingBalanceDiff: expectUnderlyingBalanceDiff,
  }: {
    usdpBalanceDiff?: string | number;
    underlyingBalanceDiff?: string | number;
    poolDataDiff?: {
      feeReserve?: string | number;
      usdpAmount?: string | number;
      poolAmount?: string | number;
    }
  }){
    if(!this.usdpBefore){
      throw new Error('call beforePurchase first.')
    }
    const usdpAfter = await this.usdp.balanceOf(this.user)
    const actualUSDPDiff = ethers.utils.formatEther(usdpAfter.sub(this.usdpBefore));
    const poolDataAfter = await this.getPoolData()
    let underlyingBalanceDiff = 0;
    this.printPoolData(poolDataAfter, 'after')
    expect(Number(actualUSDPDiff)).to.eq(Number(usdpBalanceDiff), `USDP balance don't meet`)
    if(poolDataDiff.feeReserve){
      expect(Number(ethers.utils.formatEther(poolDataAfter.feeReserve.sub(this.poolDataBefore.feeReserve)))).to.eq(Number(poolDataDiff.feeReserve), `feeReserve don't meet`)
    }
    if(poolDataDiff.usdpAmount){
      expect(Number(ethers.utils.formatEther(poolDataAfter.usdpAmount.sub(this.poolDataBefore.usdpAmount)))).to.eq(Number(poolDataDiff.usdpAmount), `usdpAmount don't meet`)
    }
    if(poolDataDiff.poolAmount){
      expect(Number(ethers.utils.formatEther(poolDataAfter.poolAmount.sub(this.poolDataBefore.poolAmount)))).to.eq(Number(poolDataDiff.poolAmount), `poolAmount don't meet`)
    }
    if(this.underlyingToken){
      const balanceNow = (await this.underlyingToken.balanceOf(this.user))
      underlyingBalanceDiff = Number(ethers.utils.formatEther(balanceNow.sub(
              this.underlyingBalanceBefore
            ).toString()))
      if(expectUnderlyingBalanceDiff){
        expect(underlyingBalanceDiff).to.eq(Number(expectUnderlyingBalanceDiff), `underlying balance don't meet, balance before: ${ethers.utils.formatEther(this.underlyingBalanceBefore)}, now: ${ethers.utils.formatEther(balanceNow)}`)
      }
    }
  }

  async getPoolData(): Promise<IPoolData>{
    const vaultInfo = await this.vault.vaultInfo(this.underlyingTokenAddress)
    return {
      feeReserve: vaultInfo[0],
      usdpAmount: vaultInfo[1],
      poolAmount: vaultInfo[2],
      reservedAmount: vaultInfo[3]
    }
  }

  printPoolData(poolData: IPoolData, mark?: string) {
    if(!this.config.verbose){
      return
    }
    console.log(`----Pool Data ${mark}, tokenSymbol: ${this.cacheAddress2Name[this.underlyingTokenAddress]} ----`)
    console.table({
      feeReserve: autoFormatEther(poolData.feeReserve),
      usdpAmount: autoFormatEther(poolData.usdpAmount.toString()),
      poolAmount: autoFormatEther(poolData.poolAmount.toString()),
      reservedAmount: autoFormatEther(poolData.reservedAmount.toString())
    })
    console.log(`----End Pool Data ${mark} ----`)
  }

}

function autoFormatEther(value: string | number | ethersE.BigNumber) {
  return {
    raw: value.toString(),
    formated: ethers.utils.formatEther(value)
  }
}

// function return value => key
// AC. given {a: 'b', c: 'd'}, return {b: 'a', d: 'c'}
function reverseObject(obj: any) {
  return Object.keys(obj).reduce((acc, key) => {
    acc[obj[key]] = key;
    return acc;
  }, {});
}

export function bigNumberify(n: string | number) {
  return ethers.BigNumber.from(`${n}`)
}

export function expandDecimals(n: string | number, decimals: number) {
  return bigNumberify(n).mul(bigNumberify(10).pow(decimals))
}

export async function getBlockTime(provider?: any, blockNumber?: number) {
  if(!provider)
    provider = ethers.getDefaultProvider()
  const block = await provider.getBlock(blockNumber || 'latest')
  return block.timestamp
}

export async function mineBlock() {
  await helpers.mine()
}

export async function increaseTime(seconds) {
  await helpers.time.increase(seconds)
}


