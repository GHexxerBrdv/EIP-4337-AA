// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC4337} from "src/EIP_4337_AA.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployERC4337 is Script {
    HelperConfig helperConfig = new HelperConfig();
    HelperConfig.NetworkConfig config = helperConfig.getConfig();
    ERC4337 erc4337;

    function run() public returns (HelperConfig, ERC4337) {
        vm.startBroadcast(config.account);
        erc4337 = new ERC4337(config.entryPoint);
        erc4337.transferOwnership(config.account);
        vm.stopBroadcast();
        return (helperConfig, erc4337);
    }
}
