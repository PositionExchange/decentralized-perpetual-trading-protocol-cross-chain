import {MigrationContext, MigrationDefinition} from "../types";
import {ContractWrapperFactory} from "../ContractWrapperFactory";
import { PLP, USDP, VaultPriceFeed, VaultUtils } from "../../typeChain";

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => ({
      'deploy mock tokens': async () => {
        await ctx.factory.createMockToken('USDT', 'USDT', 18)
        await ctx.factory.createMockToken('BUSD', 'BUSD', 18)
        await ctx.factory.createWrapableToken('WETH', 'WETH', 18)
        await ctx.factory.createWrapableToken('WBNB', 'WBNB', 18)
        await ctx.factory.createMockToken('BTC', 'BTC', 18)
        await ctx.factory.createMockToken('POSI', 'POSI', 18)
        await ctx.factory.createMockToken('DAI', 'DAI', 9)
      },
        'deploy core vault & config': async () => {
          const {usdp, plp, vaultUtils, vaultPriceFeed, vault, plpManager} = await ctx.factory.createCoreVaultContracts()
          // config vault
          await ctx.factory.waitTx(vaultUtils.initialize(vault.address), 'vaultUtils.initialize', true)
          await ctx.factory.waitTx(usdp.addVault(plpManager.address), 'usdp.addVault')
          await ctx.factory.waitTx(plp.setMinter(plpManager.address, true), 'plp.setMinter')

          await ctx.factory.waitTx(vault.setFees(
              10, // _taxBasisPoints
              5, // _stableTaxBasisPoints
              20, // _mintBurnFeeBasisPoints
              20, // _swapFeeBasisPoints
              1, // _stableSwapFeeBasisPoints
              10, // _marginFeeBasisPoints
              // TODO config me??
              (0), // _liquidationFeeUsd
              24 * 60 * 60, // _minProfitTime
              true // _hasDynamicFees
            ), "vault.setFees")
        },
        // call this one to re config price feed for tokens
        'config price feeds': async () => {
          // vault price feed set price feed config
          const {vaultPriceFeed} = await ctx.factory.createCoreVaultContracts()
          const tokens = ctx.factory.getWhitelistedTokens()
          for(let i = 0; i < tokens.length; i++) {
            const token = tokens[i]
            await ctx.factory.waitTx(vaultPriceFeed.setPriceFeedConfig(
              token.address,
              token.extraConfig.priceFeedConfig.chainLinkPriceFeed,
              token.extraConfig.priceFeedConfig.priceFeedDecimals,
              token.extraConfig.priceFeedConfig.spreadBasisPoints,
              token.extraConfig.priceFeedConfig.isStrictStable,
            ), `vaultPriceFeed.setPriceFeedConfig(${token.symbol})`)
          }
        },
        'config vault token': async () => {
          // set config for token
          const tokens = ctx.factory.getWhitelistedTokens()
          // TODO get from options
          const isSkipExist = false
          for(let i = 0; i < tokens.length; i++) {
            await ctx.factory.setConfigVaultToken(tokens[i], isSkipExist)
          }
        }
    })
}


export default migrations;
