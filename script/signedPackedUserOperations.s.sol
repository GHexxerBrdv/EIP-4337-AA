// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
// import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
import {Token} from "../src/Token.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {DeployEIP4337AA} from "../script/EIP4337AA.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IEntryPoint} from "../src/Helper/IEntryPoint.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SignedPackedUSerOperations is Script {
    using MessageHashUtils for bytes32;

    // Token token;
    address constant RECIPIENT = 0x9a581eeEfE4bed5D61a5A709CDFc704347A820bF;

    function run() external {
        // helperConfig = HelperConfig(DevOpsTools.get_most_recent_deployment("HelperConfig", block.chainid));
        HelperConfig helperConfig = new HelperConfig();

        address dest = helperConfig.getConfig().target;
        // console2.log("the address of the destination contract is: ", dest);
        uint256 value = 0;
        // address acc = DevOpsTools.get_most_recent_deployment("EIP4337AA", block.chainid);
        address acc = 0x4A71B61534741d1bD5EE39EB476855B969F06493;
        // console2.log("the address of deployed contract is: ", acc);
        bytes memory functionData = abi.encodeWithSelector(Token.mint.selector, helperConfig.getConfig().account, 50e18);
        // console2.log("the address of the account contract is: ", helperConfig.getConfig().account);
        // console2.log("the address of the entrypoint contract is: ", helperConfig.getConfig().entryPoint);
        bytes memory executionData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, functionData);

        UserOperation memory op = generateSignedUserOperation(executionData, helperConfig.getConfig(), acc);
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        vm.startBroadcast();
        // IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(vm.envAddress("ACC")));
        IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789).handleOps(ops, payable(vm.envAddress("ACC")));
        vm.stopBroadcast();

        // assert(Token(dest).balanceOf(vm.envAddress("ACC")) == 50e18);
    }

    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address account
    ) public view returns (UserOperation memory) {
        // uint256 nonce = vm.getNonce(account);
        uint256 nonce = vm.getNonce(account) - 1;
        // IEntryPoint entrypoint = IEntryPoint(config.entryPoint);
        // uint256 nonce = entrypoint.getNonce(account, 0);
        UserOperation memory op = _generateUnsignedUserOperation(callData, account, nonce);
        // console2.log("the etnry point address is : ", config.entryPoint);
        bytes32 opHash = IEntryPoint(config.entryPoint).getUserOpHash(op);
        bytes32 digest = opHash.toEthSignedMessageHash();
        // uint256 deposit = IEntryPoint(config.entryPoint).balanceOf(account);
        // console2.log("EntryPoint deposit (ETH):", deposit );
        uint8 v;
        bytes32 r;
        bytes32 s;

        uint256 Anvil_Key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(Anvil_Key, digest);
        } else {
            // (v, r, s) = vm.sign(vm.envUint("PRIV"), digest);
            (v, r, s) = vm.sign(config.account, digest);
        }

        op.signature = abi.encodePacked(r, s, v);
        return op;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        view
        returns (UserOperation memory)
    {
        // Set realistic gas values for Sepolia
        uint256 callGasLimit = 100_000; // Increased from 200k
        uint256 verificationGasLimit = 100_000; // Increased from 200k
        uint256 preVerificationGas = 50_000; // Higher than standard tx to cover bundler overhead

        // Gas fees - adjust based on current Sepolia conditions
        uint256 maxPriorityFeePerGas = 0.1e9; // 2 Gwei
        uint256 maxFeePerGas = 5e8; // 3 Gwei (base fee + priority fee)

        return UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"", // Empty for existing accounts
            callData: callData, // The actual execution call
            callGasLimit: callGasLimit,
            verificationGasLimit: verificationGasLimit,
            preVerificationGas: preVerificationGas,
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            paymasterAndData: hex"", // No paymaster
            signature: hex"" // Will be filled later
        });
    }
}

// contract fundAA is Script {
//     function run() external {
//         address aa = DevOpsTools.get_most_recent_deployment("EIP4337AA", block.chainid);
//         require(aa != address(0), "Contract should be deployed");
//         address entryPoint = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

//         vm.startBroadcast(vm.envUint("PRIV"));
//         // (bool ok,) = payable(aa).call{value: 0.02 ether}("");
//         // (ok);
//         IEntryPoint(entryPoint).depositTo{value: 0.05 ether}(aa);
//         vm.stopBroadcast();

//         uint256 deposit = IEntryPoint(entryPoint).balanceOf(aa);
//         console2.log("The balance of account in entry point contract is: ", deposit, "wei");
//     }
// }
