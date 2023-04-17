import {MigrationContext, MigrationDefinition} from "../types";
import {ContractWrapperFactory} from "../ContractWrapperFactory";
import {
  DptpFuturesGateway,
  LpManager,
  MockToken,
  PLP,
  USDP,
  Vault,
  VaultPriceFeed,
  VaultUtils,
  WETH
} from "../../typeChain";
import {BigNumber, ContractTransaction} from "ethers";

const migrations: MigrationDefinition = {
    getTasks: (ctx: MigrationContext) => {
      return {
      'deploy mock tokens': async () => {
        await ctx.factory.createMockToken('USDT', 'USDT', 18)
        await ctx.factory.createMockToken('BUSD', 'BUSD', 18)
        await ctx.factory.createWrapableToken('WETH', 'WETH', 18)
        await ctx.factory.createWrapableToken('WBNB', 'WBNB', 18)
        await ctx.factory.createMockToken('BTC', 'BTC', 18)
        // await ctx.factory.createMockToken('POSI', 'POSI', 18)
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
              24 * 60 * 60, // _minProfitTime
              false // _hasDynamicFees
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
        },

        're-config after deploy new vault': async () => {
          const deployerAddress = (await ctx.factory.hre.ethers.getSigners())[0].address
          const vaultAddress = ctx.db.findAddressByKey('Vault')

          const weth = await ctx.factory.getDeployedContract<WETH>('WETH')
          const usdt = await ctx.factory.getDeployedContract<MockToken>( 'USDT', 'MockToken')
          const busd = await ctx.factory.getDeployedContract<MockToken>('BUSD', 'MockToken')
          const lpManager = await ctx.factory.getDeployedContract<LpManager>('LpManager')
          const usdp = await ctx.factory.getDeployedContract<USDP>('USDP')
          const futuresGateway = await ctx.factory.getDeployedContract<DptpFuturesGateway>('DptpFuturesGateway')

          let tx: Promise<ContractTransaction>;

          // tx = usdp.addVault(vaultAddress)
          // await ctx.factory.waitTx(tx, 'usdp.addVault')
          //
          // tx = lpManager.setVault(vaultAddress)
          // await ctx.factory.waitTx(tx, 'lpManager.setVault')
          //
          // tx = futuresGateway.setVault(vaultAddress)
          // await ctx.factory.waitTx(tx, 'futuresGateway.setVault')
          //
          // tx = weth.mint(deployerAddress, BigNumber.from('1000000000000000000000'))
          // await ctx.factory.waitTx(tx, 'weth.mint')
          //
          // tx = weth.approve(lpManager.address, BigNumber.from('1000000000000000000000'))
          // await ctx.factory.waitTx(tx, 'weth.approve')
          //
          // tx = lpManager.addLiquidity(
          //     weth.address,
          //     BigNumber.from('1000000000000000000000'),
          //     BigNumber.from('0'),
          //     BigNumber.from('1000000000000000000')
          // )
          // await ctx.factory.waitTx(tx, 'lpManager.addLiquidity')

          tx = usdt.mint(deployerAddress, BigNumber.from('10000000000000000000000000'))
          await ctx.factory.waitTx(tx, 'usdt.mint')

          tx = usdt.approve(lpManager.address, BigNumber.from('10000000000000000000000000'))
          await ctx.factory.waitTx(tx, 'usdt.approve')

          tx = lpManager.addLiquidity(
              usdt.address,
              BigNumber.from('10000000000000000000000000'),
              BigNumber.from('0'),
              BigNumber.from('10000000000000000000000')
          )
          await ctx.factory.waitTx(tx, 'lpManager.addLiquidity.usdt')

          tx = busd.mint(deployerAddress, BigNumber.from('10000000000000000000000000'))
          await ctx.factory.waitTx(tx, 'busd.mint')

          tx = busd.approve(lpManager.address, BigNumber.from('10000000000000000000000000'))
          await ctx.factory.waitTx(tx, 'busd.approve')

          tx = lpManager.addLiquidity(
              busd.address,
              BigNumber.from('10000000000000000000000000'),
              BigNumber.from('0'),
              BigNumber.from('10000000000000000000000')
          )
          await ctx.factory.waitTx(tx, 'lpManager.addLiquidity.busd')
        },
    }}
}


export default migrations;
