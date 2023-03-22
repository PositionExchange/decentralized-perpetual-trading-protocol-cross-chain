import { ethers } from "hardhat"
import type * as ethersE from "ethers";
import {
  FactoryOptions
} from "@nomiclabs/hardhat-ethers/types";
import { MockToken, USDP, Vault } from "../../typeChain";
import { loadContractFixtures, loadMockTokenFixtures } from "./fixtures";
import { expect } from "chai";


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
  poolDataBefore: IPoolData;
  constructor(protected vault: Vault, protected usdp: USDP, protected underlyingTokenAddress: string, protected user: string, protected config: {
    verbose?: boolean
  } = {
    verbose: true
  }) {
  }
  async beforePurchase(newUnderlyingTokenAddress?: string){
    if(newUnderlyingTokenAddress){
      this.underlyingTokenAddress = newUnderlyingTokenAddress
    }
    const {usdp} = await loadMockTokenFixtures()
    const {vault} = await loadContractFixtures()
    this.vault = vault
    this.usdp = usdp
    this.usdpBefore = await usdp.balanceOf(this.user)
    this.poolDataBefore = await this.getPoolData()
    this.printPoolData(this.poolDataBefore, 'before')
  }

  async expectAfter({
    usdpBalanceDiff,
    poolDataDiff
  }: {
    usdpBalanceDiff: string | number;
    poolDataDiff: {
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
    console.log(`----Pool Data ${mark} ----`)
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
