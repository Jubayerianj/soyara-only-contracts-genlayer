// scripts/deploy-factory.js
const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("🚀 SoyaraDex V2 CORE - FACTORY DEPLOYMENT");
  console.log("=".repeat(45) + "\n");
  
  const [deployer] = await ethers.getSigners();
  console.log(`📱 Deployer: ${deployer.address}`);
  
  // === CONFIG: set your multisig/timelock address here ===
  // Replace with your real multisig (e.g. Gnosis Safe) address before running
  const PROTOCOL_MULTISIG = "0x48234eD645676b794a4CbC7483513e58cB04e22E";
  // If true, the script will also transfer feeToSetter to the multisig (recommended for production)
  const TRANSFER_FEE_TO_SETTER = true;
  // =======================================================
  
  // Get network info
  const network = await ethers.provider.getNetwork();
  const balance = await ethers.provider.getBalance(deployer.address);
  const balanceEth = ethers.formatEther(balance);
  
  console.log(`🔗 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💰 Balance: ${balanceEth} ETH\n`);
  
  // Check balance
  if (parseFloat(balanceEth) < 0.001 && network.name !== "hardhat") {
    console.log("⚠️  Warning: Low balance for deployment!");
    console.log(`   Current: ${balanceEth} ETH, Minimum: 0.001 ETH\n`);
  }
  
  try {
    // ===== 1. COMPILE CONTRACTS =====
    console.log("1️⃣  Compiling contracts...");
    await hre.run("compile");
    console.log("✅ Contracts compiled\n");
    
    // ===== 2. DEPLOY FACTORY =====
    console.log("2️⃣  Deploying SwappingDexV2Factory...");
    
    // Get the Factory contract factory
    const SwappingDexV2Factory = await ethers.getContractFactory("SwappingDexV2Factory");
    
    // Deploy with deployer as feeToSetter
    console.log("   Sending deployment transaction...");
    const factory = await SwappingDexV2Factory.deploy(deployer.address);
    
    // Get transaction hash
    const deployTx = factory.deploymentTransaction();
    console.log(`   Transaction hash: ${deployTx.hash}`);
    
    // Wait for deployment
    console.log("   Waiting for confirmation...");
    await factory.waitForDeployment();
    
    const factoryAddress = await factory.getAddress();
    console.log(`✅ Factory deployed at: ${factoryAddress}\n`);
    
    // ===== 2.a ACTIVATE PROTOCOL FEES (set feeTo to your multisig) =====
    // Ensure user replaced PROTOCOL_MULTISIG placeholder
    if (!PROTOCOL_MULTISIG || PROTOCOL_MULTISIG === "0xYOUR_MULTISIG_ADDRESS_HERE") {
      console.log("❗ PROTOCOL_MULTISIG not set. Protocol fees NOT activated.");
      console.log("   To activate, set PROTOCOL_MULTISIG in this script to your multisig address.\n");
    } else {
      // basic sanity check for address format
      if (!(typeof PROTOCOL_MULTISIG === "string" && PROTOCOL_MULTISIG.startsWith("0x") && PROTOCOL_MULTISIG.length === 42)) {
        console.log("❗ PROTOCOL_MULTISIG does not look like a valid address. Skipping activation.");
      } else {
        try {
          console.log("→ Activating protocol fee (factory.setFeeTo) to multisig...");
          const setFeeToTx = await factory.setFeeTo(PROTOCOL_MULTISIG);
          console.log(`   txHash: ${setFeeToTx.hash} — waiting for confirmation...`);
          await setFeeToTx.wait();
          console.log(`✅ factory.feeTo set to: ${PROTOCOL_MULTISIG}`);
  
          if (TRANSFER_FEE_TO_SETTER) {
            console.log("→ Transferring feeToSetter to multisig (factory.setFeeToSetter)...");
            const setFeeToSetterTx = await factory.setFeeToSetter(PROTOCOL_MULTISIG);
            console.log(`   txHash: ${setFeeToSetterTx.hash} — waiting for confirmation...`);
            await setFeeToSetterTx.wait();
            console.log(`✅ factory.feeToSetter transferred to: ${PROTOCOL_MULTISIG}`);
          } else {
            console.log("ℹ️  TRANSFER_FEE_TO_SETTER is false — feeToSetter remains deployer.");
          }
  
          console.log(""); // spacing
        } catch (err) {
          console.error("❌ Failed to activate protocol fees or transfer feeToSetter:", err);
          console.log("   You can set feeTo manually later with: factory.setFeeTo(address) from the feeToSetter account.");
          console.log("");
        }
      }
    }
    
    // ===== 3. CALCULATE INIT CODE HASH =====
    console.log("3️⃣  Calculating INIT_CODE_PAIR_HASH...");
    
    // Get Pair contract factory to access bytecode
    const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
    const pairBytecode = UniswapV2Pair.bytecode;
    
    // Calculate init code hash (used for pair address calculation)
    const initCodeHash = ethers.keccak256(pairBytecode);
    console.log(`✅ INIT_CODE_PAIR_HASH: ${initCodeHash}\n`);
    
    // ===== 4. VERIFY FACTORY DEPLOYMENT =====
    console.log("4️⃣  Verifying factory deployment...");
    
    // Check feeToSetter
    const feeToSetter = await factory.feeToSetter();
    console.log(`   feeToSetter: ${feeToSetter}`);
    console.log(`   Matches deployer: ${feeToSetter === deployer.address}`);
    
    // Also show current feeTo (protocol recipient)
    const feeToCurrent = await factory.feeTo();
    console.log(`   feeTo (protocol recipient): ${feeToCurrent}`);
    console.log(`   Matches multisig: ${PROTOCOL_MULTISIG && feeToCurrent === PROTOCOL_MULTISIG}\n`);
    
    // Check allPairs length (should be 0)
    const allPairsLength = await factory.allPairsLength();
    console.log(`   Total pairs: ${allPairsLength}\n`);
    
    // ===== 5. SAVE DEPLOYMENT INFO =====
    console.log("5️⃣  Saving deployment information...");
    
    const deploymentsDir = path.join(__dirname, "..", "deployments");
    
    // Create directories if they don't exist
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }
    
    // Network-specific directory
    const networkDir = path.join(deploymentsDir, network.name);
    if (!fs.existsSync(networkDir)) {
      fs.mkdirSync(networkDir, { recursive: true });
    }
    
    // Deployment info
    const deploymentInfo = {
      network: {
        name: network.name,
        chainId: network.chainId.toString(),
      },
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      blockNumber: await ethers.provider.getBlockNumber(),
      contracts: {
        factory: {
          address: factoryAddress,
          transactionHash: deployTx.hash,
          feeToSetter: feeToSetter,
          feeTo: await factory.feeTo()
        },
        initCodeHash: initCodeHash,
        note: "Pairs will be created dynamically via createPair() function"
      },
      protocol: {
        multisig: PROTOCOL_MULTISIG,
        transferFeeToSetter: TRANSFER_FEE_TO_SETTER
      }
    };
    
    // Save to file
    const timestamp = Date.now();
    const filename = `factory-${timestamp}.json`;
    
    fs.writeFileSync(
      path.join(networkDir, filename),
      JSON.stringify(deploymentInfo, null, 2)
    );
    
    // Also save as latest
    fs.writeFileSync(
      path.join(networkDir, "latest.json"),
      JSON.stringify(deploymentInfo, null, 2)
    );
    
    console.log(`📄 Saved to: deployments/${network.name}/${filename}`);
    console.log(`📄 Latest: deployments/${network.name}/latest.json\n`);
    
    // ===== 6. PRINT SUMMARY =====
    console.log("=".repeat(60));
    console.log("🎉 SoyaraDex V2 FACTORY DEPLOYMENT COMPLETE!");
    console.log("=".repeat(60));
    console.log(`🏭 Factory Address: ${factoryAddress}`);
    console.log(`🔑 Init Code Hash: ${initCodeHash.slice(0, 20)}...`);
    console.log(`👤 Fee To Setter: ${feeToSetter}`);
    console.log(`👥 Protocol multisig: ${PROTOCOL_MULTISIG}`);
    console.log(`🔗 Network: ${network.name} (${network.chainId})`);
    console.log("=".repeat(60));
    
    // Show useful info
    console.log("\n📋 HOW TO CREATE A PAIR:");
    console.log("1. Have two ERC20 token addresses (tokenA, tokenB)");
    console.log("2. Call: await factory.createPair(tokenA, tokenB)");
    console.log("3. Pair address will be deterministically created using CREATE2");
    
    console.log("\n⚠️  IMPORTANT NOTES:");
    console.log("• Save the INIT_CODE_PAIR_HASH above!");
    console.log("• You'll need it for Router deployment in v2-periphery");
    console.log("• Update UniswapV2Library.sol with this hash");
    console.log("• Protocol fees mint LP tokens to factory.feeTo (your multisig).");
    console.log("• Recommended: use multisig/timelock for treasury and feeToSetter control.");
    
    // Show Etherscan link if on Sepolia
    if (network.name === "sepolia") {
      console.log(`\n🔗 View on Etherscan: https://sepolia.etherscan.io/address/${factoryAddress}`);
    }
    
    // Remaining balance
    const finalBalance = await ethers.provider.getBalance(deployer.address);
    const gasUsed = ethers.formatEther(balance - finalBalance);
    console.log(`\n⛽ Gas used: ${gasUsed} ETH`);
    console.log(`💰 Remaining balance: ${ethers.formatEther(finalBalance)} ETH`);
    
    return deploymentInfo;
    
  } catch (error) {
    console.error("\n❌ DEPLOYMENT FAILED!");
    console.error("=".repeat(40));
    console.error("Error:", error.message);
    
    if (error.message.includes("bytecode")) {
      console.log("\n💡 TIP: Make sure your contracts are properly imported.");
      console.log("   Check that all interfaces and libraries exist.");
      console.log("   Try: npx hardhat clean && npx hardhat compile");
    } else if (error.message.includes("nonce")) {
      console.log("\n💡 TIP: Try resetting your account nonce");
    }
    
    throw error;
  }
}

// Run with error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Fatal error:", error);
    process.exit(1);
  });
