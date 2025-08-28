// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {UserOperation06} from "lib/account-abstraction/contracts/legacy/v06/UserOperation06.sol";
import {INonceManager06} from "lib/account-abstraction/contracts/legacy/v06/INonceManager06.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/legacy/v06/IEntryPoint06.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC4337} from "src/EIP_4337_AA.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract SendPackedUserOpUsingPaymaster is Script {
    using MessageHashUtils for bytes32;

    // Make sure you trust this user - don't run this on Mainnet!
    address public constant RANDOM_APPROVER = 0x8a6843446334983E8BF1330934B71e01f751e099;
    uint256 public allowanceAmount = 1e18;

    function run() public {
        // Setup
        HelperConfig helperConfig = new HelperConfig();
        address dest = helperConfig.getConfig().token;
        uint256 value = 0;
        address ERC4337Address = DevOpsTools.get_most_recent_deployment("ERC4337", block.chainid);
        address paymaster = DevOpsTools.get_most_recent_deployment("SimpleWhitelistPaymaster06", block.chainid);

        bytes memory functionData = abi.encodeWithSelector(IERC20.approve.selector, RANDOM_APPROVER, allowanceAmount);
        bytes memory executeCalldata = abi.encodeWithSelector(ERC4337.execute.selector, dest, value, functionData);
        UserOperation06 memory userOp =
            _buildAndSignUserOp(executeCalldata, helperConfig.getConfig(), ERC4337Address, paymaster);
        UserOperation06[] memory ops = new UserOperation06[](1);
        ops[0] = userOp;

        // Send transaction
        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(helperConfig.getConfig().account));
        vm.stopBroadcast();
    }

    function _buildAndSignUserOp(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address erc4337,
        address paymaster
    ) public view returns (UserOperation06 memory) {
        // 1. Generate the unsigned data
        uint256 nonce = INonceManager06(config.entryPoint).getNonce(erc4337, 0);
        // gas params: set reasonably high to avoid AA21 (prefund) surprises
        uint128 verificationGasLimit = 1_000_000;
        uint128 callGasLimit = 1_000_000;
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = 1 gwei;

        UserOperation06 memory userOp = UserOperation06({
            sender: erc4337,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            callGasLimit: callGasLimit,
            verificationGasLimit: verificationGasLimit,
            preVerificationGas: 21000,
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            paymasterAndData: abi.encodePacked(paymaster),
            signature: hex""
        });

        // 2. Get the userOp Hash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // 3. Sign it
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = vm.sign(vm.envUint("PRIV"), digest);

        userOp.signature = abi.encodePacked(r, s, v); // Note the order
        return userOp;
    }
}
