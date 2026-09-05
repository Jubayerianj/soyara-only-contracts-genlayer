// scripts/deploy-weth.js
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("🚀 DEPLOYING WETH9 (Wrapped GEN) on GenLayer");
  console.log("Deployer:", deployer.address);

  const WETH9 = await ethers.getContractFactory("WETH9");
  console.log("Deploying WETH9...");
  const weth = await WETH9.deploy();
  await weth.waitForDeployment();
  const wethAddress = await weth.getAddress();

  console.log("✅ WETH9 (WGEN) deployed to:", wethAddress);
  console.log("Transaction Hash:", weth.deploymentTransaction().hash);

  const out = {
    address: wethAddress,
    deployer: deployer.address,
    network: (await ethers.provider.getNetwork()).name,
    chainId: (await ethers.provider.getNetwork()).chainId.toString(),
    timestamp: new Date().toISOString()
  };

  const deploymentsDir = path.join(__dirname, "..", "deployments", "genlayer");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  fs.writeFileSync(path.join(deploymentsDir, "weth.json"), JSON.stringify(out, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
