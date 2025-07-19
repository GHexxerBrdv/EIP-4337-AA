// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PaymasterEIP4337} from "../src/Paymaster.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPaymaster is Script {
    PaymasterEIP4337 public paymaster;
    HelperConfig public helperConfig;

    function run() external returns (PaymasterEIP4337) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        paymaster = new PaymasterEIP4337(config.entryPoint, 1 ether);
        vm.stopBroadcast();

        return paymaster;
    }
}
