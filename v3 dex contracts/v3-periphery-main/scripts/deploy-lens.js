// scripts/deploy-lens.js
const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting SoyaraDex V3 Lens Contracts Deployment...\n");
  
  // GenLayer addresses
  const WETH9 = "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e";
  const FACTORY = "0xBd959038300aF0C8dd1873E497d6D0a565b4E246";
  
  try {
    // Get signer
    const [deployer] = await ethers.getSigners();
    const provider = ethers.provider;
    const network = await provider.getNetwork();
    console.log("📡 Network:", network.name, `(${network.chainId})`);
    console.log("👤 Deployer:", deployer.address);
    console.log("🏭 Factory:", FACTORY);
    console.log("💰 WETH:", WETH9);
    
    // Test connection
    console.log("Testing connection...");
    console.log("✅ Connected to chain:", network.chainId);
    
    // Check balance
    const balance = await provider.getBalance(deployer.address);
    console.log("💰 Balance:", ethers.utils.formatEther(balance), "ETH");
    
    if (balance.lt(ethers.utils.parseEther("0.01"))) {
      throw new Error("Low balance. Get Sepolia ETH from a faucet");
    }
    
    console.log("\n" + "=".repeat(50));
    console.log("Starting lens contracts deployment...");
    console.log("=".repeat(50) + "\n");
    
    // Step 1: Deploy QuoterV2
    console.log("1. Deploying QuoterV2...");
    const QuoterV2 = await ethers.getContractFactory("QuoterV2");
    const quoterV2 = await QuoterV2.deploy(FACTORY, WETH9);
    await quoterV2.deployTransaction.wait(1);
    console.log("   ✅ Address:", quoterV2.address);
    console.log("   📝 TX Hash:", quoterV2.deployTransaction.hash);
    
    // Step 2: Deploy TickLens
    console.log("\n2. Deploying TickLens...");
    const TickLens = await ethers.getContractFactory("TickLens");
    const tickLens = await TickLens.deploy();
    await tickLens.deployTransaction.wait(1);
    console.log("   ✅ Address:", tickLens.address);
    console.log("   📝 TX Hash:", tickLens.deployTransaction.hash);
    
    // Step 3: Deploy UniswapInterfaceMulticall
    console.log("\n3. Deploying UniswapInterfaceMulticall...");
    const UniswapInterfaceMulticall = await ethers.getContractFactory("UniswapInterfaceMulticall");
    const uniswapInterfaceMulticall = await UniswapInterfaceMulticall.deploy();
    await uniswapInterfaceMulticall.deployTransaction.wait(1);
    console.log("   ✅ Address:", uniswapInterfaceMulticall.address);
    console.log("   📝 TX Hash:", uniswapInterfaceMulticall.deployTransaction.hash);
    
    // Verification step (optional)
    console.log("\n" + "=".repeat(50));
    console.log("🎉 LENS CONTRACTS DEPLOYMENT COMPLETE!");
    console.log("=".repeat(50));
    console.log("\n📊 Summary:");
    console.log("-".repeat(40));
    console.log("QuoterV2:", quoterV2.address);
    console.log("TickLens:", tickLens.address);
    console.log("UniswapInterfaceMulticall:", uniswapInterfaceMulticall.address);

    const fs = require("fs");
    const summary = {
      network: network.name,
      chainId: network.chainId,
      factory: FACTORY,
      weth9: WETH9,
      quoterV2: quoterV2.address,
      tickLens: tickLens.address,
      uniswapInterfaceMulticall: uniswapInterfaceMulticall.address,
      deployer: deployer.address,
      timestamp: new Date().toISOString()
    };
    fs.writeFileSync("deploylens-info.json", JSON.stringify(summary, null, 2));
    console.log("\n📄 Saved lens deployment summary to deploylens-info.json");
    
    // Prepare verification commands
    console.log("\n🔍 Verification Commands:");
    console.log("-".repeat(40));
    console.log(`npx hardhat verify --network sepolia ${quoterV2.address} "${FACTORY}" "${WETH9}"`);
    console.log(`npx hardhat verify --network sepolia ${tickLens.address}`);
    console.log(`npx hardhat verify --network sepolia ${uniswapInterfaceMulticall.address}`);
    
  } catch (error) {
    console.error("\n❌ Error:", error.message);
    
    if (error.message.includes("network") || error.message.includes("timeout")) {
      console.log("\n🔧 Try these fixes:");
      console.log("1. Update SEPOLIA_RPC_URL in .env file");
      console.log("2. Use a different RPC provider");
      console.log("3. Check your internet connection");
    }
    
    process.exit(1);
  }
}

main();