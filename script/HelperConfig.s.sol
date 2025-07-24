// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId(uint256 chianid);

    uint256 public constant LOCAL = 31337;
    uint256 public constant POLY = 80002;
    uint256 public constant SEPO = 11155111;

    address public constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public WALLET = vm.envAddress("ACC");

    struct NetworkConfig {
        address entryPoint;
        address target;
        address account;
    }

    constructor() {
        networkConfig[POLY] = getPolygonNetworkConfig();
        networkConfig[SEPO] = getSepoliaNetworkConfig();
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainid => NetworkConfig config) public networkConfig;

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 id) public returns (NetworkConfig memory) {
        if (id == LOCAL) {
            return anvilConfig();
        } else if (id == 80002) {
            return networkConfig[POLY];
        } else if (id == 11155111) {
            return networkConfig[SEPO];
        } else {
            revert HelperConfig__InvalidChainId(id);
        }
    }

    function getSepoliaNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
            target: 0x6b233dd6d07177824634f839BB692373A76404eB,
            account: 0xA7407106D3c9a5ab2131a7AcAa343b6219Aa1Dd6
        });
    }

    function getPolygonNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x0000000071727De22E5E9d8BAf0edAc6f37da032,
            target: 0xe22062F79cef1A2F38b7682570cEAFe07C280709,
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
