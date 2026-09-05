// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentExecutor} from "../src/AgentExecutor.sol";

/// @notice Deploys ONLY AgentExecutor against the already-deployed aggregator
///         and DEX contracts. Used to ship the multi-agent authorisation change
///         without redeploying the whole stack.
contract DeployExecutorOnly is Script {
    function run() external {
        uint256 pk = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address entrypoint = 0x95feE6Cb918Ed9C621E36082EE8D998873031EaA;
        address v2Router   = 0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5;
        address v3PosMgr   = 0x779380011B5F2aB40985D810B5c7641539beD870;

        address[] memory approvedTokens = new address[](6);
        approvedTokens[0] = 0x315374AA9b5536037Cc1Efeea2439CCC0913A77e; // WGEN
        approvedTokens[1] = 0x58B6CD7891cd0A682226E25607b958a6479195A6; // USDC
        approvedTokens[2] = 0x4B54235778c26Ee8ac27744A53d4c5BC4c9D46fc; // USDT
        approvedTokens[3] = 0x723534bc6C2B536fF5D0455111513A9431c44e25; // WBTC
        approvedTokens[4] = 0x0F56b4E7f4e2cf346a94aB9263Ed3F3644db7c0C; // ETH
        approvedTokens[5] = 0xA2eC9aAf2235C66491767e69eBBD885469697B3E; // FSWP

        vm.startBroadcast(pk);
        AgentExecutor exec = new AgentExecutor(
            deployer,   // owner
            deployer,   // primary authorised agent
            entrypoint,
            v2Router,
            v3PosMgr,
            300,        // max slippage bps
            approvedTokens
        );
        vm.stopBroadcast();

        console.log("AgentExecutor:", address(exec));
        console.log("owner/agent  :", deployer);
    }
}
