import "@nomiclabs/hardhat-waffle";
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import "@openzeppelin/hardhat-upgrades"
import "@typechain/hardhat";
import "hardhat-contract-sizer"
import "@openzeppelin/hardhat-defender"
import {task} from "hardhat/config";
import {
    BSC_MAINNET_URL,
    BSC_TESTNET_URL, GANACHE_QC_URL, OKEX_CHAIN_MAINNET_URL, OKEX_CHAIN_TESTNET_URL,
    POSI_CHAIN_DEVNET_URL,
    POSI_CHAIN_TESTNET_URL, PRIV_GANACHE_ACCOUNT, PRIV_MAINNET_ACCOUNT,
    PRIV_POSI_CHAIN_DEVNET_ACCOUNT,
    PRIV_POSI_CHAIN_TESTNET_ACCOUNT, PRIV_TESTNET_ACCOUNT,
    // VOLTA_ACCOUNT,
    // VOLTA_CHAIN_ID,
    // VOLTA_EXPLORER_API_KEY,
    // VOLTA_EXPLORER_URL,
    // VOLTA_RPC_URL
} from "./constants";
import "./scripts/deploy";
// TODO enable gas reporter once development done
// import "hardhat-gas-reporter";
import "solidity-coverage";
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
            url: BSC_TESTNET_URL,
            chainId: 97,
            accounts: PRIV_TESTNET_ACCOUNT ? [PRIV_TESTNET_ACCOUNT] : [],
        },
        bsc: {
            url: BSC_MAINNET_URL,
            chainId: 56,
            accounts: PRIV_MAINNET_ACCOUNT ? [PRIV_MAINNET_ACCOUNT] : [],
        },
        geth: {
            url: GANACHE_QC_URL,
            chainId: 930000,
            accounts: PRIV_GANACHE_ACCOUNT ? [PRIV_GANACHE_ACCOUNT] : [],
        },
        posi_devnet: {
            url: POSI_CHAIN_DEVNET_URL,
            chainId: 920000,
            accounts: PRIV_POSI_CHAIN_DEVNET_ACCOUNT ? [PRIV_POSI_CHAIN_DEVNET_ACCOUNT] : [],
        },
        posi_testnet: {
            url: POSI_CHAIN_TESTNET_URL,
            chainId: 910000,
            accounts: PRIV_POSI_CHAIN_TESTNET_ACCOUNT ? [PRIV_POSI_CHAIN_TESTNET_ACCOUNT] : [],
        },
        // volta: {
        //     url: VOLTA_RPC_URL,
        //     chainId: VOLTA_CHAIN_ID,
        //     accounts: VOLTA_ACCOUNT ? [VOLTA_ACCOUNT] : [],
        // },
        okex_testnet: {
            url: OKEX_CHAIN_TESTNET_URL,
            chainId: 65,
            accounts: PRIV_POSI_CHAIN_TESTNET_ACCOUNT ? [PRIV_POSI_CHAIN_TESTNET_ACCOUNT] : [],
        },
        okex_mainnet: {
            url: OKEX_CHAIN_MAINNET_URL,
            chainId: 66,
            accounts: PRIV_MAINNET_ACCOUNT ? [PRIV_MAINNET_ACCOUNT] : [],
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
            posi_devnet: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            posi_testnet: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            // bscTestnet: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            bsc: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            geth: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            // okex_testnet: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6',
            // okex_mainnet: 'UXFZRYWHB141CX97CPECWH9V7E9QSPHUF6'
        },
        customChains: [
            {
                network: "posi_devnet",
                chainId: 920000,
                urls: {
                    apiURL: "https://blockscout-devnet.int.posichain.org/api",
                    browserURL: "https://blockscout-devnet.int.posichain.org"
                }
            },
            {
                network: "posi_testnet",
                chainId: 910000,
                urls: {
                    apiURL: "https://apex-testnet.posichain.org/contract-verifier/verify",
                    browserURL: "http://explorer-testnet.posichain.org"
                }
            },
            {
                network: "geth",
                chainId: 930000,
                urls: {
                    apiURL: 'https://explorer.nonprodposi.com/api',
                    browserURL: 'https://explorer.nonprodposi.com/'
                }
            },
            // {
            //     network: "okex_testnet",
            //     chainId: 65,
            //     urls: {
            //         apiURL: 'https://www.oklink.com/okexchain-test/api',
            //         browserURL: 'https://www.oklink.com/okexchain-test/'
            //     }
            // },
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
    }
};

