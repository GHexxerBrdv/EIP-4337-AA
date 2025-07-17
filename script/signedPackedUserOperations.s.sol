// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {Token} from "../src/Token.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {DeployEIP4337AA} from "../script/EIP4337AA.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract SignedPackedUSerOperations is Script {
    using MessageHashUtils for bytes32;

    EIP4337AA aa;
    HelperConfig helperConfig;
    Token token;

    function run() external {
        helperConfig = new HelperConfig();

        address dest = helperConfig.getConfig().target;
        uint256 value = 0;
        address acc = DevOpsTools.get_most_recent_deployment("EIP4337AA", block.chainid);

        bytes memory functionData = abi.encodeWithSelector(Token.mint.selector, helperConfig.getConfig().account, 1e18);
        bytes memory executionData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, functionData);

        PackedUserOperation memory op = generateSignedUserOperation(executionData, helperConfig.getConfig(), acc);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(vm.envAddress("ACC2")));
        vm.stopBroadcast();

        assert(Token(dest).balanceOf(vm.envAddress("ACC")) == 1e18);
    }

    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address account
    ) public view returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(account) - 1;
        PackedUserOperation memory op = _generateUnsignedUserOperation(callData, account, nonce);

        bytes32 opHash = IEntryPoint(config.entryPoint).getUserOpHash(op);
        bytes32 digest = opHash.toEthSignedMessageHash();

        uint8 v;
        bytes32 r;
        bytes32 s;

        uint256 Anvil_Key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(Anvil_Key, digest);
        } else {
            (v, r, s) = vm.sign(vm.envUint("PRIV"), digest);
        }

        op.signature = abi.encodePacked(r, s, v);
        return op;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit)),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas)),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}

contract fundAA is Script {
    function run() external {
        address aa = DevOpsTools.get_most_recent_deployment("EIP4337AA", block.chainid);

        vm.startBroadcast(vm.envUint("PRIV"));
        (bool ok,) = payable(aa).call{value: 0.05 ether}("");
        (ok);
        vm.stopBroadcast();

        assert(aa.balance == 0.05 ether);
    }
}
