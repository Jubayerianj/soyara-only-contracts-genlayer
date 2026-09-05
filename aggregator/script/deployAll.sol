// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AGGFlowRouter} from "../src/flow/AGGFlow.sol";
import {AGGFlowEntrypoint} from "../src/entrypoint/AGGFlowEntrypoint.sol";

/**
 * @title deployAll
 * @notice One‑command deployment script for AGGFlow on Somnia (Mainnet)
 */
contract deployAll is Script {
    function run() public {
        // ----------------------------------------------------------------------
        //  HARDCODED SOMNIA CONFIGURATION
        // ----------------------------------------------------------------------
        string memory rpcUrl = "https://liteforge.rpc.caldera.xyz/http";   // Somnia Mainnet RPC
        address wethAddress = 0x315374AA9b5536037Cc1Efeea2439CCC0913A77e; // WSOMI (Wrapped SOMI) address
        address flowOwner   = 0x48234eD645676b794a4CbC7483513e58cB04e22E; // Your owner address

        // ----------------------------------------------------------------------
        //  READ DEPLOYER PRIVATE KEY FROM ENVIRONMENT
        // ----------------------------------------------------------------------
        uint256 deployerPrivateKey = vm.envUint("GOV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // ----------------------------------------------------------------------
        //  CHECKS
        // ----------------------------------------------------------------------
        require(wethAddress != address(0), "WSOMI address not set");
        require(flowOwner != address(0), "Owner address not set");

        console.log("Deploying AGGFlow to Somnia Mainnet");
        console.log("Deployer:", deployer);
        console.log("Owner:   ", flowOwner);
        console.log("WSOMI:   ", wethAddress);
        console.log("RPC URL: ", rpcUrl);
        console.log("------------------------------------------------");

        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the AGGFlowRouter (pass WSOMI address)
        AGGFlowRouter router = new AGGFlowRouter(wethAddress);
        console.log("AGGFlowRouter deployed to: ", address(router));

        // 2. Deploy the AGGFlowEntrypoint (pass owner and router address)
        AGGFlowEntrypoint entrypoint = new AGGFlowEntrypoint(flowOwner, address(router));
        console.log("AGGFlowEntrypoint deployed to: ", address(entrypoint));

        vm.stopBroadcast();

        console.log("------------------------------------------------");
        console.log("Deployment completed successfully!");
        console.log("AGGFlowRouter:     ", address(router));
        console.log("AGGFlowEntrypoint: ", address(entrypoint));
        console.log("Owner:             ", flowOwner);
        console.log("------------------------------------------------");
    }
}