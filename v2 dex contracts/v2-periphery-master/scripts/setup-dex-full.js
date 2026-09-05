// scripts/setup-dex-full.js
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Helper: encode sqrtPriceX96 from ratio amount1/amount0
function encodeSqrtPriceX96(amount1, amount0) {
  // sqrt(amount1 / amount0) * 2^96
  // Using BigInt arithmetic
  const ONE_96 = 2n ** 96n;
  // ratio = (amount1 * 10^18) / amount0
  const ratioX1e18 = (BigInt(amount1) * 10n ** 18n) / BigInt(amount0);
  // sqrt in integer: approx
  let sqrtRatio = sqrtBigInt(ratioX1e18); // this is sqrt(ratio) * 10^9
  // sqrtPriceX96 = (sqrtRatio * 2^96) / 10^9
  const sqrtPriceX96 = (sqrtRatio * ONE_96) / (10n ** 9n);
  return sqrtPriceX96;
}

function sqrtBigInt(n) {
  if (n < 0n) throw new Error("negative number");
  if (n === 0n) return 0n;
  let x0 = n / 2n;
  if (x0 !== 0n) {
    let x1 = (x0 + n / x0) / 2n;
    while (x1 < x0) {
      x0 = x1;
      x1 = (x0 + n / x0) / 2n;
    }
    return x0;
  }
  return 1n;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const provider = ethers.provider;
  const network = await provider.getNetwork();
  console.log("==================================================");
  console.log("🚀 STARTING COMPLETE DEX SETUP ON GENLAYER");
  console.log("==================================================");
  console.log("👤 Deployer:", deployer.address);
  console.log("🔗 Network:", network.name, `(${network.chainId})`);
  
  const balance = await provider.getBalance(deployer.address);
  console.log("💰 Native Balance:", ethers.formatEther(balance), "GEN");

  // Existing deployed addresses on GenLayer (4221)
  const WGEN_ADDRESS = "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e";
  const V2_FACTORY_ADDRESS = "0x4680BCe1632824d30D2F53656dD610736c3e312e";
  const V2_ROUTER_ADDRESS = "0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5";
  const V3_FACTORY_ADDRESS = "0xBd959038300aF0C8dd1873E497d6D0a565b4E246";
  const V3_POSITION_MANAGER = "0x779380011B5F2aB40985D810B5c7641539beD870";
  const V3_SWAP_ROUTER = "0xdf69970B2fE416339187aA41D39882e864984CE9";
  const AGG_ROUTER_ADDRESS = "0xDF474006aa807598B616500d146FfF661d644138";
  const AGG_ENTRYPOINT_ADDRESS = "0xfdf5cD6452EDC340e67cd16db6A9D74aaa4f81a3";

  // 1. DEPLOY ERC20 TOKENS
  console.log("\n==================================================");
  console.log("1️⃣  DEPLOYING ERC20 TEST TOKENS");
  console.log("==================================================");

  const CustomERC20 = await ethers.getContractFactory("CustomERC20");

  const tokensConfig = [
    { name: "USD Coin", symbol: "USDC", decimals: 18, supply: ethers.parseEther("10000000") },
    { name: "Tether USD", symbol: "USDT", decimals: 18, supply: ethers.parseEther("10000000") },
    { name: "Wrapped Bitcoin", symbol: "WBTC", decimals: 18, supply: ethers.parseEther("1000") },
    { name: "Ethereum", symbol: "ETH", decimals: 18, supply: ethers.parseEther("10000") },
    { name: "FlipSwap Token", symbol: "FSWP", decimals: 18, supply: ethers.parseEther("5000000") },
  ];

  const deployedTokens = {};

  for (const t of tokensConfig) {
    console.log(`Deploying ${t.symbol} (${t.name})...`);
    const token = await CustomERC20.deploy(t.name, t.symbol, t.decimals, t.supply);
    await token.waitForDeployment();
    const addr = await token.getAddress();
    deployedTokens[t.symbol] = {
      address: addr,
      name: t.name,
      symbol: t.symbol,
      decimals: t.decimals,
      contract: token
    };
    console.log(`✅ ${t.symbol} deployed at: ${addr}`);
  }

  // 2. WRAP NATIVE GEN INTO WGEN
  console.log("\n==================================================");
  console.log("2️⃣  WRAPPING 20 GEN INTO WGEN");
  console.log("==================================================");

  const WETH9 = await ethers.getContractFactory("WETH9");
  const wgen = WETH9.attach(WGEN_ADDRESS);

  const depositTx = await wgen.deposit({ value: ethers.parseEther("20") });
  await depositTx.wait();
  console.log("✅ Wrapped 20 GEN into WGEN");
  const wgenBalance = await wgen.balanceOf(deployer.address);
  console.log("💰 WGEN Balance:", ethers.formatEther(wgenBalance));

  // 3. ADD LIQUIDITY ON V2
  console.log("\n==================================================");
  console.log("3️⃣  ADDING LIQUIDITY ON SoyaraDex V2");
  console.log("==================================================");

  const V2Router = await ethers.getContractFactory("SwappingDexV2Router02");
  const v2Router = V2Router.attach(V2_ROUTER_ADDRESS);

  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // Approve V2 Router for all tokens
  const maxApproval = ethers.MaxUint256;
  for (const sym of Object.keys(deployedTokens)) {
    console.log(`Approving ${sym} for V2 Router...`);
    const tx = await deployedTokens[sym].contract.approve(V2_ROUTER_ADDRESS, maxApproval);
    await tx.wait();
  }
  const approveWgenV2 = await wgen.approve(V2_ROUTER_ADDRESS, maxApproval);
  await approveWgenV2.wait();

  // V2 Pair 1: GEN / USDC (5 GEN + 1000 USDC)
  console.log("\nAdding V2 Liquidity: GEN / USDC (5 GEN + 1000 USDC)...");
  const addGenUsdcTx = await v2Router.addLiquidityETH(
    deployedTokens["USDC"].address,
    ethers.parseEther("1000"),
    0,
    0,
    deployer.address,
    deadline,
    { value: ethers.parseEther("5") }
  );
  await addGenUsdcTx.wait();
  console.log("✅ V2 Pool GEN/USDC created & liquidity added!");

  // V2 Pair 2: GEN / USDT (5 GEN + 1000 USDT)
  console.log("\nAdding V2 Liquidity: GEN / USDT (5 GEN + 1000 USDT)...");
  const addGenUsdtTx = await v2Router.addLiquidityETH(
    deployedTokens["USDT"].address,
    ethers.parseEther("1000"),
    0,
    0,
    deployer.address,
    deadline,
    { value: ethers.parseEther("5") }
  );
  await addGenUsdtTx.wait();
  console.log("✅ V2 Pool GEN/USDT created & liquidity added!");

  // V2 Pair 3: USDC / USDT (10,000 USDC + 10,000 USDT)
  console.log("\nAdding V2 Liquidity: USDC / USDT (10,000 USDC + 10,000 USDT)...");
  const addUsdcUsdtTx = await v2Router.addLiquidity(
    deployedTokens["USDC"].address,
    deployedTokens["USDT"].address,
    ethers.parseEther("10000"),
    ethers.parseEther("10000"),
    0,
    0,
    deployer.address,
    deadline
  );
  await addUsdcUsdtTx.wait();
  console.log("✅ V2 Pool USDC/USDT created & liquidity added!");

  // V2 Pair 4: GEN / WBTC (5 GEN + 0.025 WBTC)
  console.log("\nAdding V2 Liquidity: GEN / WBTC (5 GEN + 0.025 WBTC)...");
  const addGenWbtcTx = await v2Router.addLiquidityETH(
    deployedTokens["WBTC"].address,
    ethers.parseEther("0.025"),
    0,
    0,
    deployer.address,
    deadline,
    { value: ethers.parseEther("5") }
  );
  await addGenWbtcTx.wait();
  console.log("✅ V2 Pool GEN/WBTC created & liquidity added!");

  // V2 Pair 5: GEN / FSWP (5 GEN + 5000 FSWP)
  console.log("\nAdding V2 Liquidity: GEN / FSWP (5 GEN + 5000 FSWP)...");
  const addGenFswpTx = await v2Router.addLiquidityETH(
    deployedTokens["FSWP"].address,
    ethers.parseEther("5000"),
    0,
    0,
    deployer.address,
    deadline,
    { value: ethers.parseEther("5") }
  );
  await addGenFswpTx.wait();
  console.log("✅ V2 Pool GEN/FSWP created & liquidity added!");

  // 4. ADD LIQUIDITY ON V3
  console.log("\n==================================================");
  console.log("4️⃣  ADDING LIQUIDITY ON SoyaraDex V3");
  console.log("==================================================");

  // PositionManager ABI
  const positionManagerAbi = [
    "function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) external payable returns (address pool)",
    "function mint((address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline)) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)"
  ];
  const positionManager = new ethers.Contract(V3_POSITION_MANAGER, positionManagerAbi, deployer);

  // Approve PositionManager
  for (const sym of Object.keys(deployedTokens)) {
    console.log(`Approving ${sym} for V3 PositionManager...`);
    const tx = await deployedTokens[sym].contract.approve(V3_POSITION_MANAGER, maxApproval);
    await tx.wait();
  }
  const approveWgenV3 = await wgen.approve(V3_POSITION_MANAGER, maxApproval);
  await approveWgenV3.wait();

  // Helper to setup V3 Pool
  async function setupV3Pool(tokenA, tokenB, fee, amountA, amountB, tickSpacing) {
    const isToken0 = tokenA.toLowerCase() < tokenB.toLowerCase();
    const token0 = isToken0 ? tokenA : tokenB;
    const token1 = isToken0 ? tokenB : tokenA;
    const amount0 = isToken0 ? amountA : amountB;
    const amount1 = isToken0 ? amountB : amountA;

    // Price ratio = amount1 / amount0
    const sqrtPriceX96 = encodeSqrtPriceX96(amount1, amount0);
    console.log(`Initializing V3 Pool (${token0.slice(0,6)} / ${token1.slice(0,6)}) with fee ${fee}...`);

    const initTx = await positionManager.createAndInitializePoolIfNecessary(
      token0,
      token1,
      fee,
      sqrtPriceX96
    );
    await initTx.wait();
    console.log("✅ Pool initialized");

    // Mint wide position: tickLower & tickUpper aligned to tickSpacing
    const maxTick = 887220 - (887220 % tickSpacing);
    const minTick = -maxTick;

    console.log(`Minting V3 position [${minTick}, ${maxTick}]...`);
    const mintParams = {
      token0: token0,
      token1: token1,
      fee: fee,
      tickLower: minTick,
      tickUpper: maxTick,
      amount0Desired: amount0,
      amount1Desired: amount1,
      amount0Min: 0,
      amount1Min: 0,
      recipient: deployer.address,
      deadline: Math.floor(Date.now() / 1000) + 3600
    };

    const mintTx = await positionManager.mint(mintParams);
    const receipt = await mintTx.wait();
    console.log(`✅ V3 Liquidity minted! (tx: ${receipt.hash})`);
  }

  // V3 Pool 1: WGEN / USDC (fee 3000, 5 WGEN + 1000 USDC)
  console.log("\nV3 Pool 1: WGEN / USDC (fee 3000)...");
  await setupV3Pool(
    WGEN_ADDRESS,
    deployedTokens["USDC"].address,
    3000,
    ethers.parseEther("5"),
    ethers.parseEther("1000"),
    60
  );

  // V3 Pool 2: USDC / USDT (fee 500, 10,000 USDC + 10,000 USDT)
  console.log("\nV3 Pool 2: USDC / USDT (fee 500)...");
  await setupV3Pool(
    deployedTokens["USDC"].address,
    deployedTokens["USDT"].address,
    500,
    ethers.parseEther("10000"),
    ethers.parseEther("10000"),
    10
  );

  // V3 Pool 3: WGEN / USDT (fee 3000, 5 WGEN + 1000 USDT)
  console.log("\nV3 Pool 3: WGEN / USDT (fee 3000)...");
  await setupV3Pool(
    WGEN_ADDRESS,
    deployedTokens["USDT"].address,
    3000,
    ethers.parseEther("5"),
    ethers.parseEther("1000"),
    60
  );

  // 5. TEST SWAP USING V2 & V3 ROUTERS & AGGREGATOR
  console.log("\n==================================================");
  console.log("5️⃣  EXECUTING TEST SWAPS ON GENLAYER DEX");
  console.log("==================================================");

  // V2 Swap: Swap 0.1 GEN for USDC
  console.log("Executing V2 Swap: 0.1 GEN -> USDC...");
  const swapPath = [WGEN_ADDRESS, deployedTokens["USDC"].address];
  const swapTx = await v2Router.swapExactETHForTokens(
    0,
    swapPath,
    deployer.address,
    deadline,
    { value: ethers.parseEther("0.1") }
  );
  const swapReceipt = await swapTx.wait();
  console.log(`✅ V2 Swap Successful! (tx: ${swapReceipt.hash})`);

  const usdcBalance = await deployedTokens["USDC"].contract.balanceOf(deployer.address);
  console.log("💰 Deployer USDC Balance:", ethers.formatEther(usdcBalance));

  // Save tokens data to JSON
  const tokensSummary = {
    GEN: { symbol: "GEN", name: "GEN", address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", decimals: 18, isNative: true },
    WGEN: { symbol: "WGEN", name: "Wrapped GEN", address: WGEN_ADDRESS, decimals: 18, isNative: false },
    USDC: { symbol: "USDC", name: "USD Coin", address: deployedTokens["USDC"].address, decimals: 18 },
    USDT: { symbol: "USDT", name: "Tether USD", address: deployedTokens["USDT"].address, decimals: 18 },
    WBTC: { symbol: "WBTC", name: "Wrapped Bitcoin", address: deployedTokens["WBTC"].address, decimals: 18 },
    ETH: { symbol: "ETH", name: "Ethereum", address: deployedTokens["ETH"].address, decimals: 18 },
    FSWP: { symbol: "FSWP", name: "FlipSwap Token", address: deployedTokens["FSWP"].address, decimals: 18 },
  };

  const outPath = path.join(__dirname, "..", "deployments", "genlayer", "tokens.json");
  fs.writeFileSync(outPath, JSON.stringify(tokensSummary, null, 2));
  console.log("\n📄 Saved token addresses to:", outPath);

  console.log("\n==================================================");
  console.log("🎉 ALL TOKENS DEPLOYED, LIQUIDITY ADDED ON V2 & V3, AND TEST SWAPS COMPLETED!");
  console.log("==================================================");
}

main().catch((error) => {
  console.error("\n❌ Setup failed:", error);
  process.exit(1);
});
