import { MigrationContext, MigrationDefinition } from "../types";
import {
  DptpFuturesGateway,
  GatewayUtils,
  LpManager,
  MockToken,
  RewardRouter, ShortsTracker,
  USDP,
  Vault, VaultPriceFeed, VaultReader,
  VaultUtils, VaultUtilsSplit,
  WETH,
} from "../../typeChain";
import { BigNumber, ContractTransaction } from "ethers";
import {SUBTASK_NAME} from "../tasks/common";
import {run} from "hardhat";

const migrations: MigrationDefinition = {
  getTasks: (ctx: MigrationContext) => {
    return {
      "deploy mock tokens without transfer upgradeable": async () => {
        await ctx.factory.createUpgradeableToken("USDT", "USDT", 6);
        // await ctx.factory.createWrapableToken("WETH", "WETH", 18);
        await ctx.factory.createUpgradeableToken("BTC", "BTC", 8);
        await ctx.factory.createUpgradeableToken("DAI", "DAI", 18);
        await ctx.factory.createUpgradeableToken("LINK", "LINK", 18);
        await ctx.factory.createUpgradeableToken("USDC", "USDC", 6);
      },

      "deploy mock tokens": async () => {
        await ctx.factory.createMockToken("USDT", "USDT", 6);
        await ctx.factory.createWrapableToken("WETH", "WETH", 18);
        await ctx.factory.createMockToken("BTC", "BTC", 8);
        await ctx.factory.createMockToken("DAI", "DAI", 18);
        await ctx.factory.createMockToken("LINK", "LINK", 18);
        await ctx.factory.createMockToken("USDC", "USDC", 6);
      },
      "upgrade vault": async () => {
        const vault = await ctx.db.findAddressByKey("Vault");
        if (vault) {
          await ctx.factory.createVault("", "", "");
          return;
        }
      },
      "force import vault": async () => {
        const vault = await ctx.db.findAddressByKey("Vault");
        const factory = await ctx.hre.ethers.getContractFactory("Vault");
        if (vault) {
          await ctx.hre.upgrades.forceImport(vault, factory);
          return;
        }
      },

      "deploy vault utils": async () => {
        const vaultUtils = await ctx.factory.createVaultUtils();
        const vault = await ctx.factory.getDeployedContract<Vault>('Vault')
        await ctx.factory.waitTx(
            vaultUtils.initialize(vault.address),
            "vaultUtils.initialize",
            true
        );
      },

      "deploy core vault & config": async () => {
        const { usdp, plp, vaultUtils, vaultPriceFeed, vault, plpManager } =
          await ctx.factory.createCoreVaultContracts();
        // config vault
        await ctx.factory.waitTx(
          vaultUtils.initialize(vault.address),
          "vaultUtils.initialize",
          true
        );
        await ctx.factory.waitTx(
          usdp.addVault(vault.address),
          "usdp.addVault"
        );
        await ctx.factory.waitTx(
          plp.setMinter(plpManager.address, true),
          "plp.setMinter"
        );

        await ctx.factory.waitTx(
          vault.setFees(
            10, // _taxBasisPoints
            5, // _stableTaxBasisPoints
            20, // _mintBurnFeeBasisPoints
            20, // _swapFeeBasisPoints
            1, // _stableSwapFeeBasisPoints
            10, // _marginFeeBasisPoints
            24 * 60 * 60, // _minProfitTime
            true // _hasDynamicFees
          ),
          "vault.setFees"
        );
      },
      // call this one to re config price feed for tokens
      "config price feeds": async () => {
        // vault price feed set price feed config
        const vaultPriceFeed = await ctx.factory.getDeployedContract<VaultPriceFeed>("VaultPriceFeed")
        const tokens = ctx.factory.getWhitelistedTokens();
        for (let i = 0; i < tokens.length; i++) {
          const token = tokens[i];
          await ctx.factory.waitTx(
            vaultPriceFeed.setPriceFeedConfig(
              token.address,
              token.extraConfig.priceFeedConfig.chainLinkPriceFeed,
              token.extraConfig.priceFeedConfig.priceFeedDecimals,
              token.extraConfig.priceFeedConfig.spreadBasisPoints,
              token.extraConfig.priceFeedConfig.isStrictStable
            ),
            `vaultPriceFeed.setPriceFeedConfig(${token.symbol})`
          );
        }
      },

      "config vault token": async () => {
        // set config for token
        const tokens = ctx.factory.getWhitelistedTokens();
        // TODO get from options
        const isSkipExist = false;
        for (let i = 0; i < tokens.length; i++) {
          await ctx.factory.setConfigVaultToken(tokens[i], isSkipExist);
        }
      },

      "re-config after deploy new vault": async () => {

        const vaultAddress = ctx.db.findAddressByKey("Vault");

        const lpManager = await ctx.factory.getDeployedContract<LpManager>(
          "LpManager"
        );
        const usdp = await ctx.factory.getDeployedContract<USDP>("USDP");
        const vaultUtils = await ctx.factory.getDeployedContract<VaultUtils>(
          "VaultUtils"
        );
        const gatewayUtils =
          await ctx.factory.getDeployedContract<GatewayUtils>("GatewayUtils");
        const rewardRouter =
          await ctx.factory.getDeployedContract<RewardRouter>("RewardRouter");

        // const shortTracker =
        //   await ctx.factory.getDeployedContract<ShortsTracker>("ShortsTracker");
        const vaultUtilsSplit =
          await ctx.factory.getDeployedContract<VaultUtilsSplit>("VaultUtilsSplit");

        let tx: Promise<ContractTransaction>;

        await run(SUBTASK_NAME.VAULT_SetFuturXGateway, {
          ctx: ctx,
        });

        // tx = usdp.addVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "usdp.addVault");
        //
        // tx = lpManager.setVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "lpManager.setVault");

        // await run(SUBTASK_NAME.FGW_SetVault, {
        //   ctx: ctx
        // });

        // tx = vaultUtils.setVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "vaultUtils.setVault");
        //
        // tx = gatewayUtils.setVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "gatewayUtils.setVault");
        //
        // tx = rewardRouter.setGov(vaultAddress);
        // await ctx.factory.waitTx(tx, "rewardRouter.setGov");

        // tx = shortTracker.setVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "rewardRouter.setGov");

        // tx = vaultUtilsSplit.setVault(vaultAddress);
        // await ctx.factory.waitTx(tx, "vaultUtilsSplit.setVault");
      },

      "mint and approve": async () => {
        const gateway =
          await ctx.factory.getDeployedContract<DptpFuturesGateway>(
            "DptpFuturesGateway"
          );
        const weth = await ctx.factory.getDeployedContract<WETH>("WETH");

        const signers = await ctx.hre.ethers.getSigners();

        const amount = BigNumber.from("100000000000000000000");

        for (const signer of signers) {
          await ctx.factory.waitTx(
            weth.mint(signer.address, amount),
            `minting weth for ${signer.address}`
          );
          await ctx.factory.waitTx(
            weth.approve(gateway.address, amount),
            `minting weth for ${signer.address}`
          );
        }

        for (const token of ["USDC", "USDT", "DAI", "BTC", "LINK"]) {
          const contract = await ctx.factory.getDeployedContract<MockToken>(
            token,
            "MockToken"
          );
          for (const signer of signers) {
            await ctx.factory.waitTx(
              contract.mint(signer.address, amount),
              `minting ${token} for ${signer.address}`
            );
            await ctx.factory.waitTx(
              contract.approve(gateway.address, amount),
              `minting ${token} for ${signer.address}`
            );
          }
        }
      },
    };
  },
};

export default migrations;
