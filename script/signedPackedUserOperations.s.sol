// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract SignedPackedUSerOperations is Script {
    using MessageHashUtils for bytes32;

    function run() external {}

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
            (v, r, s) = vm.sign(config.account, digest);
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
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
