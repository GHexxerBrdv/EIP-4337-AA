// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SimpleWhitelistPaymaster06} from "src/Paymaster2.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployPaymaster is Script {
    HelperConfig helperConfig = new HelperConfig();
    HelperConfig.NetworkConfig config = helperConfig.getConfig();
    SimpleWhitelistPaymaster06 paymaster;

    function run() public returns (HelperConfig, SimpleWhitelistPaymaster06) {
        vm.startBroadcast(config.account);
        paymaster = new SimpleWhitelistPaymaster06(config.entryPoint);
        vm.stopBroadcast();
        return (helperConfig, paymaster);
    }
}
