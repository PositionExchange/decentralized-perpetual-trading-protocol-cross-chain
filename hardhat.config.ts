import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "hardhat-contract-sizer";
import "@openzeppelin/hardhat-defender";
import "hardhat-docgen";
import { task } from "hardhat/config";
import {
    ARB_API_KEY,
    ARB_MAINNET_DEPLOYER_KEY,
    ARB_TESTNET_DEPLOYER_KEY, BSC_API_KEY,
    BSC_MAINNET_DEPLOYER_KEY,
    BSC_TESTNET_DEPLOYER_KEY,
} from "./constants";
import "./scripts/deploy";
import "./deploy/tasks/subtasks.ts";
// TODO enable gas reporter once development done
// import "hardhat-gas-reporter";
import "solidity-coverage";
// import "@symblox/hardhat-abi-gen";
import * as tdly from "@tenderly/hardhat-tenderly";

tdly.setup({ automaticVerifications: false });

// const BSC_TESTNET_URL =
//     `${process.env["BSC_TESTNET_ENDPOINT"]}` || "https://data-seed-prebsc-1-s1.binance.org:8545/"
// const BSC_MAINNET_URL = `${process.env["BSC_MAINNET_ENDPOINT"]}`
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
    const accounts = await hre.ethers.getSigners();
    for (const account of accounts) {
        console.log(account.address);
    }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    defaultNetwork: "hardhat",

    networks: {
        localhost: {
            url: "http://127.0.0.1:8545"
        },
        hardhat: {
            allowUnlimitedContractSize: true,
        },
        bscTestnet: {
            url: "https://data-seed-prebsc-1-s2.binance.org:8545",
            chainId: 97,
            accounts: [BSC_TESTNET_DEPLOYER_KEY],
        },
        bsc: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            accounts: [BSC_MAINNET_DEPLOYER_KEY],
        },
        arbitrumGoerli: {
            url: "https://snowy-dimensional-wave.arbitrum-goerli.quiknode.pro/5fb1a4cbaec64e964facf89b037dabd44bd73b27/",
            chainId: 421613,
            accounts: [ARB_TESTNET_DEPLOYER_KEY],
        },
        arbitrumOne: {
            url: "https://arb-mainnet-public.unifra.io",
            chainId: 42161,
            gasPrice: 100000000,
            accounts: [ARB_MAINNET_DEPLOYER_KEY],
        },
    },

    solidity: {
        compilers: [
            {
                version: "0.8.9",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.8.8",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.8.0",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.6.0",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.8.2",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            }

        ]
    },
    etherscan: {
        apiKey: {
            bscTestnet: BSC_API_KEY,
            bsc: BSC_API_KEY,
            arbitrumGoerli: ARB_API_KEY,
            arbitrumOne: ARB_API_KEY,
        },
        customChains: [
            {
                network: "posi_testnet",
                chainId: 910000,
                urls: {
                    apiURL: "https://apex-testnet.posichain.org/contract-verifier/verify",
                    browserURL: "http://explorer-testnet.posichain.org"
                }
            }
        ]
    },
    defender: {
        apiKey: process.env.DEFENDER_TEAM_API_KEY,
        apiSecret: process.env.DEFENDER_TEAM_API_SECRET_KEY,
    },
    typechain: {
        outDir: "typeChain",
        target: "ethers-v5",
    },
    contractSizer: {
        strict: true
    },
    mocha: {
        timeout: 100000
    },
    abiExporter: {
        path: './abi',
        clear: true,
        spacing: 2,
        runOnCompile: true,
    },
    docgen: {
      path: './docs',
    }
};

