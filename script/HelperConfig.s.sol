// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId(uint256 chianid);

    uint256 public constant LOCAL = 31337;
    uint256 public constant POLY = 80002;

    address public constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant WALLET = 0xA7407106D3c9a5ab2131a7AcAa343b6219Aa1Dd6;

    struct NetworkConfig {
        address entryPoint;
        address target;
        address account;
    }

    constructor() {
        networkConfig[POLY] = getPolygonNetworkConfig();
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainid => NetworkConfig config) public networkConfig;

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 id) public returns (NetworkConfig memory) {
        if (id == LOCAL) {
            return anvilConfig();
        } else if (networkConfig[id].account != address(0)) {
            return networkConfig[id];
        } else {
            revert HelperConfig__InvalidChainId(id);
        }
    }

    function getPolygonNetworkConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x43370240c309f6cC0815929a176609267971224F,
            target: 0xac4206661B9992c5F140558c0C09227681cf1C07,
            account: WALLET
        });
    }

    function anvilConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.account != address(0)) {
            return localNetworkConfig;
        }

        console2.log("Deploying mocks...");
        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
        EntryPoint entryPoint = new EntryPoint();
        ERC20Mock erc20Mock = new ERC20Mock();
        vm.stopBroadcast();
        console2.log("Mocks deployed!");

        localNetworkConfig =
            NetworkConfig({entryPoint: address(entryPoint), target: address(erc20Mock), account: ANVIL_DEFAULT_ACCOUNT});
        return localNetworkConfig;
    }
}
