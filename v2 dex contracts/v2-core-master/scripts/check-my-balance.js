// scripts/check-my-balance.js
const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  // Use environment variables
  const privateKey = process.env.PRIVATE_KEY;
  const rpcUrl = process.env.SEPOLIA_RPC_URL || "https://sepolia.infura.io/v3/YOUR_PROJECT_ID";
  
  if (!privateKey) {
    console.error("❌ PRIVATE_KEY not found in .env file");
    console.log("Your .env file should contain:");
    console.log("PRIVATE_KEY=your_private_key_here");
    return;
  }
  
  // Create provider and wallet
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log("🔍 Checking wallet info...\n");
  console.log("📍 Address:", wallet.address);
  console.log("📋 Expected: 0x23D542DCEFb00b1f4268E67a0EC1EF4de0A58fe2");
  console.log("✅ Match:", wallet.address.toLowerCase() === "0x23D542DCEFb00b1f4268E67a0EC1EF4de0A58fe2".toLowerCase());
  
  const balance = await provider.getBalance(wallet.address);
  console.log("\n💰 Balance:", ethers.formatEther(balance), "ETH");
  
  // Get gas price
  const feeData = await provider.getFeeData();
  console.log("⛽ Gas Price:", ethers.formatUnits(feeData.gasPrice, "gwei"), "gwei");
  
  // Check network
  const network = await provider.getNetwork();
  console.log("\n🔗 Network:", network.name, "(Chain ID:", network.chainId + ")");
  
  if (balance === 0n) {
    console.log("\n❌ ZERO BALANCE! Get test ETH from:");
    console.log("1. https://sepoliafaucet.com/");
    console.log("2. https://www.alchemy.com/faucets/ethereum-sepolia");
    console.log("3. https://faucet.quicknode.com/ethereum/sepolia");
    console.log("\nSend to address:", wallet.address);
  } else {
    console.log("\n✅ Ready to deploy!");
    console.log("Run: npx hardhat run scripts/deploy-factory.js --network sepolia");
  }
}

main().catch(console.error);