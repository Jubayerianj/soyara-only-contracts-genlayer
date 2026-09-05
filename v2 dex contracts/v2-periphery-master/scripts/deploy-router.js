// scripts/deploy-router.js (inkonchain VERSION)
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// BigInt JSON Replacer - ADD THIS
const bigIntReplacer = (key, value) => {
  return typeof value === 'bigint' ? value.toString() : value;
};


// === CONFIG: update these before running ===
// Replace WETH_ADDRESS with the actual wrapped-native token on inkonchain (checksum address)
const WETH_ADDRESS = "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e";
// Factory address deployed earlier on inkonchain
const FACTORY_ADDRESS = "0x4680BCe1632824d30D2F53656dD610736c3e312e";
// Network metadata for frontend/deployment files
const NETWORK_NAME = "litvm";



const CHAIN_ID = 4441;
// The init code pair hash you computed during factory deployment
const INIT_CODE_PAIR_HASH = "01888feb01db41d97ad6fb1883d7e286650d46c410b82338aeb4a37554c28bcd";

// ============================================

async function main() {
  const [deployer] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;
  const networkName = network.name;
  console.log(`🚀 SoyaraDex V2 ROUTER DEPLOYMENT (${networkName})\n`);
  
  console.log("Deployer:", deployer.address);
  console.log("Factory:", FACTORY_ADDRESS);
  console.log("Wrapped native (WETH):", WETH_ADDRESS);
  console.log("Network:", networkName, `(chainId: ${chainId})`);
  
  // Deploy router

  console.log("\n1️⃣  Getting Router contract factory...");
  const Router = await ethers.getContractFactory("SwappingDexV2Router02");
  
  console.log("2️⃣  Deploying Router contract...");
  const router = await Router.deploy(FACTORY_ADDRESS, WETH_ADDRESS);
  
  console.log("   Sending deployment transaction...");
  const deployTx = router.deploymentTransaction();
  console.log(`   Transaction hash: ${deployTx.hash}`);
  
  console.log("   Waiting for confirmation...");
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  
  console.log("\n✅ Router deployed:", routerAddress);
  console.log("Transaction:", deployTx.hash);
  
  // Save deployment info
  const deployment = {
    router: routerAddress,
    factory: FACTORY_ADDRESS,
    weth_like: WETH_ADDRESS,
    deployer: deployer.address,
    network: networkName,
    chainId: chainId.toString(),
    timestamp: new Date().toISOString(),
    blockNumber: (await ethers.provider.getBlockNumber()).toString() // Convert to string for safety
  };
  
  // Ensure deployments directory exists
  const deploymentsDir = path.join(__dirname, "..", "deployments", networkName);
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const filename = `router-${Date.now()}.json`;
  const filepath = path.join(deploymentsDir, filename);
  const latestPath = path.join(deploymentsDir, "latest.json");
  
  // Use the replacer as the second argument, space as third
  fs.writeFileSync(
    filepath,
    JSON.stringify(deployment, bigIntReplacer, 2)
  );
  
  // Also save latest
  fs.writeFileSync(
    latestPath,
    JSON.stringify(deployment, bigIntReplacer, 2)
  );
  
  console.log("\n📄 Deployment saved to", filepath);
  console.log("📄 Latest saved to", latestPath);
  
  // Show config for frontend
  const frontendConfig = {
    chainId: chainId.toString(),
    factory: FACTORY_ADDRESS,
    router: routerAddress,
    weth: WETH_ADDRESS,
    initCodeHash: INIT_CODE_PAIR_HASH
  };
  
  console.log("\n📋 FRONTEND CONFIG:");
  console.log(JSON.stringify(frontendConfig, null, 2));
  
  // Explorer link: inkonchain explorer unknown here — print router address for convenience
  console.log("\n🔎 Router address (copy for explorer):", routerAddress);
  console.log("\n🎉 Router deployment complete.");
}

main().catch((error) => {
  console.error("\n❌ Deployment failed:");
  console.error(error);
  process.exitCode = 1;
});
