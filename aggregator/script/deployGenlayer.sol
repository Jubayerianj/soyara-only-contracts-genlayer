// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AGGFlowRouter} from "../src/flow/AGGFlow.sol";
import {AGGFlowEntrypoint} from "../src/entrypoint/AGGFlowEntrypoint.sol";
import {AgentExecutor} from "../src/AgentExecutor.sol";

/**
 * @title deployGenlayer
 * @notice One-command deployment script for AGGFlow + AgentExecutor on GenLayer Testnet (Chain ID 4221)
 *
 * @dev Run with:
 *   forge script script/deployGenlayer.sol --rpc-url https://rpc.testnet-chain.genlayer.com \
 *       --private-key $GOV_PRIVATE_KEY --broadcast
 *
 * After deployment, copy the AgentExecutor address printed in the logs into:
 *   frontend/flipswap/constants/addresses.js  →  CONTRACT_ADDRESSES[4221].agentExecutor
 *   frontend/flipswap/.env.local               →  AGENT_EXECUTOR_ADDRESS=<address>
 *   frontend/flipswap/.env.local               →  AGENT_PRIVATE_KEY=<deployer_pk>
 */
contract deployGenlayer is Script {
    function run() public {
        string memory rpcUrl       = "https://rpc.testnet-chain.genlayer.com";
        address wethAddress        = 0x315374AA9b5536037Cc1Efeea2439CCC0913A77e; // WGEN
        address flowOwner          = 0x48234eD645676b794a4CbC7483513e58cB04e22E; // Owner / fee vault

        // Approved tokens for AgentExecutor whitelist
        address usdc    = 0x58B6CD7891cd0A682226E25607b958a6479195A6;
        address usdt    = 0x4B54235778c26Ee8ac27744A53d4c5BC4c9D46fc;
        address wbtc    = 0x723534bc6C2B536fF5D0455111513A9431c44e25;
        address eth     = 0x0F56b4E7f4e2cf346a94aB9263Ed3F3644db7c0C;
        address fswp    = 0xA2eC9aAf2235C66491767e69eBBD885469697B3E;
        address v2Router = 0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5;
        address v3PosMgr = 0x779380011B5F2aB40985D810B5c7641539beD870;

        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        require(wethAddress != address(0), "WGEN address not set");
        require(flowOwner   != address(0), "Owner address not set");

        console.log("=== Soyara / FlipSwap DEX - GenLayer Testnet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:   ", flowOwner);
        console.log("WGEN:    ", wethAddress);
        console.log("RPC URL: ", rpcUrl);
        console.log("-----------------------------------------------------------");

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the AGGFlowRouter (pass WGEN address)
        AGGFlowRouter router = new AGGFlowRouter(wethAddress);
        console.log("AGGFlowRouter deployed to:    ", address(router));

        // 2. Deploy the AGGFlowEntrypoint (pass owner and router address)
        AGGFlowEntrypoint entrypoint = new AGGFlowEntrypoint(flowOwner, address(router));
        console.log("AGGFlowEntrypoint deployed to:", address(entrypoint));

        // 3. Deploy AgentExecutor — the one-time approval gate between
        //    GenLayer AgentValidator IC and on-chain settlement.
        //
        //    _owner            = flowOwner (admin control)
        //    _authorisedAgent  = deployer  (the off-chain agent wallet that calls
        //                                   approveTradeWithParams + executeSwap)
        //    _aggFlowEntrypoint = entrypoint
        //    _v2Router          = V2 router
        //    _v3PositionManager = V3 NonfungiblePositionManager
        //    _maxSlippageBps    = 300 (3%)
        //    _initialApprovedTokens = the full token whitelist

        address[] memory approvedTokens = new address[](6);
        approvedTokens[0] = wethAddress; // WGEN
        approvedTokens[1] = usdc;
        approvedTokens[2] = usdt;
        approvedTokens[3] = wbtc;
        approvedTokens[4] = eth;
        approvedTokens[5] = fswp;

        AgentExecutor agentExecutor = new AgentExecutor(
            flowOwner,          // _owner
            deployer,           // _authorisedAgent  (deployer wallet = the agent)
            address(entrypoint), // _aggFlowEntrypoint
            v2Router,           // _v2Router
            v3PosMgr,           // _v3PositionManager
            300,                // _maxSlippageBps (3%)
            approvedTokens      // _initialApprovedTokens
        );
        console.log("AgentExecutor deployed to:    ", address(agentExecutor));

        vm.stopBroadcast();

        console.log("===========================================================");
        console.log("DEPLOYMENT COMPLETE - Copy these into addresses.js:");
        console.log("===========================================================");
        console.log("AGGFlowRouter:     ", address(router));
        console.log("AGGFlowEntrypoint: ", address(entrypoint));
        console.log("AgentExecutor:     ", address(agentExecutor));
        console.log("Owner/Agent:       ", flowOwner);
        console.log("===========================================================");
        console.log("NEXT STEPS:");
        console.log("1. Set CONTRACT_ADDRESSES[4221].agentExecutor =", address(agentExecutor));
        console.log("2. Set AGENT_EXECUTOR_ADDRESS=", address(agentExecutor), "in .env.local");
        console.log("3. Set AGENT_PRIVATE_KEY=<GOV_PRIVATE_KEY> in .env.local");
        console.log("===========================================================");
    }
}
