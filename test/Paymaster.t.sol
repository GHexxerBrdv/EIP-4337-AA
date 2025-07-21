// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployPaymaster} from "../script/Paymaster.s.sol";
import {PaymasterEIP4337} from "../src/Paymaster.sol";
import {SignedPackedUSerOperations, PackedUserOperation} from "../script/signedPackedUserOperations.s.sol";
import {Token} from "../src/Token.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP4337AA} from "../src/EIP_4337_AA.sol";
import {DeployEIP4337AA} from "../script/EIP4337AA.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract PaymasterTest is Test {
    using MessageHashUtils for bytes32;

    DeployPaymaster public deployer;
    PaymasterEIP4337 public paymaster;
    SignedPackedUSerOperations userOp;
    Token public usdc;
    EIP4337AA acc;
    HelperConfig config;

    uint256 public constant AMOUNT = 1 ether;

    function setUp() public {
        deployer = new DeployPaymaster();
        paymaster = deployer.run();
        userOp = new SignedPackedUSerOperations();
        usdc = new Token();
        DeployEIP4337AA deploy = new DeployEIP4337AA();
        (config, acc) = deploy.deployMinimalAccount();
        address admin = makeAddr("admin");
        vm.deal(admin, 20 ether);

        payable(address(paymaster)).call{value: 10e18}("");
    }

    function test_construction() public {
        assertEq(address(paymaster).balance, 10 ether);
        assertEq(paymaster.maxSponsorship(), 1 ether);
        console2.log("the address of an entrypoint contract is: ", address(paymaster.i_entryPoint()));
        console2.log("the address of an entrypoint contract is: ", config.getConfig().entryPoint);
    }

    function test_userOp() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
        bytes memory callData = abi.encodeWithSelector(EIP4337AA.execute.selector, dest, value, functionData);

        PackedUserOperation memory op = userOp.generateSignedUserOperation(callData, config.getConfig(), address(acc));
        bytes32 opHash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(op);

        vm.prank(config.getConfig().entryPoint);
        paymaster.validatePaymasterUserOp(op, opHash, 1500);
    }
}
