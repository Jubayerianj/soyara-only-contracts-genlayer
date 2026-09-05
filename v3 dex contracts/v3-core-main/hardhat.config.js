require('hardhat-typechain');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-etherscan');
require('dotenv').config();

const accounts = process.env.PRIVATE_KEY
  ? [process.env.PRIVATE_KEY.startsWith("0x") ? process.env.PRIVATE_KEY : "0x" + process.env.PRIVATE_KEY]
  : [];

module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    litvm: {
      url: process.env.LITVM_RPC_URL || "https://liteforge.rpc.caldera.xyz/infra-partner-http",
      chainId: 4441,
      accounts: accounts,
    },
    genlayer: {
      url: process.env.GENLAYER_RPC_URL || "https://rpc-bradbury.genlayer.com",
      chainId: 4221,
      accounts: accounts,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "https://ethereum-sepolia-public.nodies.app",
      chainId: 11155111,
      accounts: accounts,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
      metadata: {
        bytecodeHash: 'none',
      },
    },
  },
};
