// scripts/deploy-agent-executor.js
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("==================================================");
  console.log("🤖 DEPLOYING AGENT EXECUTOR ON GENLAYER");
  console.log("==================================================");
  console.log("👤 Deployer:", deployer.address);

  // Whitelisted routers
  const routers = [
    "0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5", // V2 Router
    "0xdf69970B2fE416339187aA41D39882e864984CE9", // V3 Router
    "0x779380011B5F2aB40985D810B5c7641539beD870", // V3 Position Manager
    "0xDF474006aa807598B616500d146FfF661d644138", // AGGFlowRouter
    "0xfdf5cD6452EDC340e67cd16db6A9D74aaa4f81a3", // AGGFlowEntrypoint
  ];

  // Whitelisted tokens
  const tokens = [
    "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", // Native GEN
    "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e", // WGEN
    "0x58B6CD7891cd0A682226E25607b958a6479195A6", // USDC
    "0x4B54235778c26Ee8ac27744A53d4c5BC4c9D46fc", // USDT
    "0x723534bc6C2B536fF5D0455111513A9431c44e25", // WBTC
    "0x0F56b4E7f4e2cf346a94aB9263Ed3F3644db7c0C", // ETH
    "0xA2eC9aAf2235C66491767e69eBBD885469697B3E", // FSWP
  ];

  const AgentExecutor = await ethers.getContractFactory("AgentExecutor");
  console.log("Deploying AgentExecutor...");
  const executor = await AgentExecutor.deploy(routers, tokens);
  await executor.waitForDeployment();
  const executorAddress = await executor.getAddress();

  console.log("✅ AgentExecutor deployed at:", executorAddress);
  console.log("Whitelisted Routers:", routers.length);
  console.log("Whitelisted Tokens:", tokens.length);
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exit(1);
});
