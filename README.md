# soyara-only-contracts-genlayer


deployed addresses 


export const CONTRACT_ADDRESSES = {
  4221: {
    factory: "0x4680BCe1632824d30D2F53656dD610736c3e312e",
    router: "0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5",
    weth: "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    wgen: "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    WGEN: "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    wrappedNative: "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    WETH: "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    aggregatorRouter: '0xafCAD2bf0E85e30a2b54ac6491dC81987cE7767C',
    aggregatorEntrypoint: '0x95feE6Cb918Ed9C621E36082EE8D998873031EaA',
    dexFeeVault: '0x48234eD645676b794a4CbC7483513e58cB04e22E',
    // SoyaraDex V3
    v3Factory: "0xBd959038300aF0C8dd1873E497d6D0a565b4E246",
    v3Router: "0xdf69970B2fE416339187aA41D39882e864984CE9",
    v3NftDescriptor: "0xef334fcAA42A17CF8f76627408Ee0cE91eBaE6E4",
    v3NftPositionDescriptor: "0xbC5a5E695a70208Bd18B742C6731C749F1748795",
    v3PositionManager: "0x779380011B5F2aB40985D810B5c7641539beD870",
    v3Migrator: "0xa338b743Ec494ebB8345f4B6F27ffC902b7EF5Aa",
    v3Quoter: "0xca4914407868bc37ccbE324cA149DD475d39A2Bf",
    v3TickLens: "0xCa4c7EdB398684cB4C5B3fD0cc6ced30b5a5f4d3",
    multicall: "0x6d1503E294b122Eb6B37ECe9c74d24D83f8B478b",
    // GenLayer Intelligent Contracts
    // AgentValidator redeployed 2026-09-04: fixed stale router whitelist (was blocking
    // every real proposal after AGGFlowEntrypoint/AGGFlowRouter were redeployed) and
    // removed non-deterministic time.time() usage. See DEPLOYMENTS.md.
    agentValidator: "0x7ABa94668afC24463Be323f9bB65BD4b4F480d89",
    liquidityValidator: "0xEFb9473B5269A79d72Df4b6E73E310791a185eeC",
    // AgentExecutor - deployed 2026-09-04 on GenLayer Bradbury Testnet (chain 4221)
    // Tx: broadcast/deployGenlayer.sol/4221/run-latest.json
    // Deployer/Agent: 0x23D542DCEFb00b1f4268E67a0EC1EF4de0A58fe2
    agentExecutor: "0xa835c0a86dD64726eF23D83a8ca7D60b542EE2e4",
  }
};

export const INTELLIGENT_CONTRACTS = {
  agentValidator: "0x7ABa94668afC24463Be323f9bB65BD4b4F480d89",
  liquidityValidator: "0xEFb9473B5269A79d72Df4b6E73E310791a185eeC"
};
