// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";

contract DeployToken is Script {
    Token public token;

    function run() external returns (Token) {
        vm.startBroadcast(vm.envUint("PRIV"));
        token = new Token();
        vm.stopBroadcast();
        return token;
    }
}
