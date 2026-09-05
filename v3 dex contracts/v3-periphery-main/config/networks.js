// config/networks.js
module.exports = {
  sepolia: {
    chainId: 11155111,
    nativeCurrencyLabel: "ETH",
    weth9: "0xfff9976782d46cc05630d1f6ebab18b2324d6b14",
  
    factory: "0xDC07E623197a4B5036086333EC7FAfC91f5fdD3F", 
    explorer: "https://sepolia.etherscan.io",
    rpcUrl: process.env.SEPOLIA_RPC_URL || "https://ethereum-sepolia.gateway.tatum.io"
  },
  mainnet: {
    chainId: 1,
    nativeCurrencyLabel: "ETH",
    weth9: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    explorer: "https://etherscan.io",
    rpcUrl: process.env.MAINNET_RPC_URL
  },
  arbitrum: {
    chainId: 42161,
    nativeCurrencyLabel: "ETH",
    weth9: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    explorer: "https://arbiscan.io",
    rpcUrl: process.env.ARBITRUM_RPC_URL
  },
  polygon: {
    chainId: 137,
    nativeCurrencyLabel: "MATIC",
    weth9: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    explorer: "https://polygonscan.com",
    rpcUrl: process.env.POLYGON_RPC_URL
  },
  optimism: {
    chainId: 10,
    nativeCurrencyLabel: "ETH",
    weth9: "0x4200000000000000000000000000000000000006",
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    explorer: "https://optimistic.etherscan.io",
    rpcUrl: process.env.OPTIMISM_RPC_URL
  },
  // Add more networks as needed
  custom: {
    // For custom deployments
    chainId: null, // Must be set
    nativeCurrencyLabel: "ETH",
    weth9: null, // Must be set
    factory: null, // Deploy new factory if null
    explorer: null,
    rpcUrl: null // Must be set
  }
};