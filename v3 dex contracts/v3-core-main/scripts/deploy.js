const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy UniswapV3Factory
  const UniswapV3Factory = await ethers.getContractFactory("UniswapV3Factory");
  const factory = await UniswapV3Factory.deploy();
  await factory.deployed();
  
  console.log("UniswapV3Factory deployed to:", factory.address);

  // Verify fee tiers are set correctly
  const fee500 = await factory.feeAmountTickSpacing(500);
  const fee3000 = await factory.feeAmountTickSpacing(3000);
  const fee10000 = await factory.feeAmountTickSpacing(10000);
  
  console.log("Fee tier 0.05% tick spacing:", fee500.toString());
  console.log("Fee tier 0.30% tick spacing:", fee3000.toString());
  console.log("Fee tier 1.00% tick spacing:", fee10000.toString());

  // Save deployment addresses to a file
  const fs = require("fs");
  const network = await ethers.provider.getNetwork();
  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId,
    uniswapV3Factory: factory.address,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
  };

  fs.writeFileSync(
    "deployment-info.json",
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("Deployment info saved to deployment-info.json");

  return {
    factory: factory.address
  };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });