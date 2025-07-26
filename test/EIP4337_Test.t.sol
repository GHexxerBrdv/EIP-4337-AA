// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {
    SignedPackedUSerOperations,
    PackedUserOperation,
    IEntryPoint,
    UserOperation
} from "../script/signedPackedUserOperations.s.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {DeployEIP4337AA} from "../script/EIP4337AA.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Token} from "../src/Token.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EIP4337Test is Test {
    using MessageHashUtils for bytes32;

    EIP4337AA acc;
    HelperConfig config;
    Token usdc;
    SignedPackedUSerOperations userOp;

    uint256 public constant AMOUNT = 1e18;

    function setUp() public {
        DeployEIP4337AA deployer = new DeployEIP4337AA();
        (config, acc) = deployer.deployMinimalAccount();
        usdc = new Token();
        userOp = new SignedPackedUSerOperations();
    }

    function test_Construction() public view {
        console2.log("the address of the entry point contract is:", acc.getEntryPint());
        console2.log("the owner of the smart account is: ", acc.owner());
    }

    function test_Mint() public {
        assertEq(usdc.balanceOf(address(acc)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);

        address entryPoint = acc.getEntryPint();
        vm.prank(entryPoint);
        acc.execute(dest, value, callData);

        assertEq(usdc.balanceOf(address(acc)), 1e18);
    }

    function test_MintNonEntrypoint() public {
        assertEq(usdc.balanceOf(address(acc)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);

        address user = makeAddr("user");
        vm.prank(user);
        vm.expectRevert(EIP4337AA.EIP4337AA__NotFromEntryPoint.selector);
        acc.execute(dest, value, callData);

        assertEq(usdc.balanceOf(address(acc)), 0);
    }

    function test_Signature() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
        bytes memory executeData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, callData);

        UserOperation memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));

        bytes32 hash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(op);
        address signatory = ECDSA.recover(hash.toEthSignedMessageHash(), op.signature);

        assertEq(signatory, acc.owner());
    }

    function test_validateUserOp() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
        bytes memory executeData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, callData);

        UserOperation memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));
        // PackedUserOperation memory packedOp = PackedUserOperation(
        //     op.sender,
        //     op.nonce,
        //     op.initCode,
        //     op.callData,
        //     op.accountGasLimits,
        //     op.preVerificationGas,
        //     op.gasFees,
        //     op.paymasterAndData,
        //     op.signature
        // );
        bytes32 userOperationHash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(op);

        uint256 missingAccountFunds = 1e18;
        vm.deal(address(acc), 2e18);
        vm.prank(config.getConfig().entryPoint);
        uint256 ok = acc.validateUserOp(op, userOperationHash, missingAccountFunds);
        assertEq(ok, 0);
    }

    function test_EntrypointExecute() public {
        uint256 balanceBefore = config.getConfig().entryPoint.balance;
        address user = makeAddr("user");
        assertEq(usdc.balanceOf(address(acc)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
        bytes memory executeData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, callData);

        UserOperation memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));

        vm.deal(address(acc), 0.03 ether);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        vm.prank(user);
        IEntryPoint(config.getConfig().entryPoint).handleOps(ops, payable(user));
        assertEq(usdc.balanceOf(address(acc)), 1e18);
        uint256 balanceAfter = config.getConfig().entryPoint.balance;
        console2.log("the balance of entry point contract is", balanceAfter - balanceBefore);
        console2.log("the remaining amount in acc: ", address(acc).balance);
        console2.log("the original balance of the account is:", address(acc).balance + (balanceAfter - balanceBefore));
    }
}
