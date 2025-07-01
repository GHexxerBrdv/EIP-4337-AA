// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployEIP4337AA is Script {
    EIP4337AA public aa;

    function run() external returns (HelperConfig, EIP4337AA) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        aa = new EIP4337AA(config.entryPoint);
        vm.stopBroadcast();

        console2.log("The owner of aa", aa.owner());
        return (helperConfig, aa);
    }
}
