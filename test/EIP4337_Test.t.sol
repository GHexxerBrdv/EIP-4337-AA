// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC4337} from "src/EIP_4337_AA.sol";
import {DeployERC4337} from "script/EIP4337AA.s.sol";
import {DeployPaymaster} from "script/Paymaster.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {SignedPackedUSerOperations} from "../script/signedPackedUserOperations.s.sol";
import {SendPackedUserOpUsingPaymaster} from "script/SendPackedUserOpViaPaymaster.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/legacy/v06/IEntryPoint06.sol";
import {IPaymaster06} from "lib/account-abstraction/contracts/legacy/v06/IPaymaster06.sol";
import {UserOperation06} from "lib/account-abstraction/contracts/legacy/v06/UserOperation06.sol";
import {INonceManager06} from "lib/account-abstraction/contracts/legacy/v06/INonceManager06.sol";
import {IStakeManager06} from "lib/account-abstraction/contracts/legacy/v06/IStakeManager06.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {SimpleWhitelistPaymaster06} from "src/Paymaster2.sol";

contract ERC4337Test is Test {
    ERC4337 accountForAA;
    DeployERC4337 deployer;
    DeployPaymaster deployer2;
    SignedPackedUSerOperations bundlerWork;
    SendPackedUserOpUsingPaymaster bundlerWork2;
    HelperConfig helperConfig;
    IEntryPoint entryPoint;
    SimpleWhitelistPaymaster06 paymaster;
    UserOperation06[] ops;

    function setUp() public {
        deployer = new DeployERC4337();
        deployer2 = new DeployPaymaster();
        (helperConfig, accountForAA) = deployer.run();
        (, paymaster) = deployer2.run();
        bundlerWork = new SignedPackedUSerOperations();
        bundlerWork2 = new SendPackedUserOpUsingPaymaster();

        entryPoint = IEntryPoint(helperConfig.getConfig().entryPoint);
        // paymaster = new SimpleWhitelistPaymaster06(address(entryPoint));
    }

    function testExecutionInERC4337Account() public {
        // Arrange
        address TESTER_ACCOUNT = makeAddr("tester_account");
        uint256 transferAmount = 1e18;
        address dest = helperConfig.getConfig().token;
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(IERC20.transfer.selector, TESTER_ACCOUNT, transferAmount);

        // Act
        uint256 balanceBefore = IERC20(dest).balanceOf(TESTER_ACCOUNT);
        deal(dest, address(accountForAA), transferAmount);
        vm.startPrank(helperConfig.getConfig().account);
        accountForAA.execute(dest, value, functionData);
        vm.stopPrank();

        // Assert
        uint256 balanceAfter = IERC20(dest).balanceOf(TESTER_ACCOUNT);
        assertEq(balanceAfter, balanceBefore + transferAmount);
    }

    function testExecuteFailsInsufficientBalance() public {
        address payable recipient = payable(address(0xdead));
        uint256 value = 1 ether; // account has 0 ETH
        bytes memory functionData = hex"";

        vm.prank(helperConfig.getConfig().account);
        vm.expectRevert();
        accountForAA.execute(recipient, value, functionData);
    }

    function testExecutionIsPossibleOnlyThroughEntryPointOrOwner() public {
        // Arrange
        address DUMMY_ADDRESS = makeAddr("dummy");
        address TESTER_ACCOUNT = makeAddr("tester_account");
        uint256 transferAmount = 1e18;
        address dest = helperConfig.getConfig().token;
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(IERC20.transfer.selector, TESTER_ACCOUNT, transferAmount);

        // Act, Assert
        deal(dest, DUMMY_ADDRESS, transferAmount);
        vm.startPrank(DUMMY_ADDRESS);
        vm.expectRevert(ERC4337.ERC4337__NotFromEntryPointOrOwner.selector);
        accountForAA.execute(dest, value, functionData);
        vm.stopPrank();
    }

    function testValidateUserOpWorking() public {
        // 1. create dummy owner with a dummy private key
        (address dummyOwner, uint256 dummyPk) = makeAddrAndKey("dummyOwnerForTesting");

        // 2. deploy a fresh ERC4337 account with dummyOwner as the owner
        vm.prank(dummyOwner);
        ERC4337 account = new ERC4337(address(entryPoint));

        // 3. fetch nonce from EntryPoint
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(account), 0);

        // Arrange
        // 4. build the UserOp
        UserOperation06 memory userOp = UserOperation06({
            sender: address(account),
            nonce: nonce,
            initCode: hex"",
            callData: hex"",
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: hex"",
            signature: hex""
        });

        // 5. get userOpHash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // 6. sign with dummy private key
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dummyPk, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // 7. set up prefund
        uint256 missingAccountFund = 0.1 ether;
        uint256 entryPointBalanceBefore = address(entryPoint).balance;

        // Give account ETH to pay prefund
        vm.deal(address(account), 1 ether);

        // Act
        // 8. validate userOp
        vm.prank(address(entryPoint)); // only EntryPoint can call
        uint256 validationData = account.validateUserOp(userOp, userOpHash, missingAccountFund);

        // Assert
        assertEq(validationData, SIG_VALIDATION_SUCCESS); // SIG_VALIDATION_SUCCESS = 0
        assertEq(address(entryPoint).balance, entryPointBalanceBefore + missingAccountFund);
    }

    function testValidateUserOpCanOnlyBeExecutedByEntryPoint() public {
        // Arrange
        address invalidAddress = makeAddr("Dummy");
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(accountForAA), 0);
        UserOperation06 memory userOp = UserOperation06({
            sender: address(accountForAA),
            nonce: nonce,
            initCode: hex"",
            callData: hex"",
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: hex"",
            signature: hex""
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        uint256 missingAccountFund = 0.1 ether;

        // Act, Assert
        vm.prank(invalidAddress); // only EntryPoint can call
        vm.expectRevert(ERC4337.ERC4337__NotFromEntryPoint.selector);
        accountForAA.validateUserOp(userOp, userOpHash, missingAccountFund);
    }

    function testValidateUserOp_InvalidSignature() public {
        // 1. Dummy owner for invalid signature
        (, uint256 dummyPk) = makeAddrAndKey("dummyOwner");

        // 2. Fetch the current nonce
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(accountForAA), 0);

        // 3. Build a UserOperation with some callData
        UserOperation06 memory userOp = UserOperation06({
            sender: address(accountForAA),
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)), // arbitrary call
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: hex"",
            signature: hex"" // INVALID signature
        });

        // 4. Get userOpHash
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dummyPk, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // 5. Prank as EntryPoint and call validateUserOp
        vm.prank(address(entryPoint));
        uint256 validationData = accountForAA.validateUserOp(userOp, userOpHash, 0);

        // 6. Assert that validation fails
        assertEq(validationData, SIG_VALIDATION_FAILED); // SIG_VALIDATION_FAILED = 1
    }

    function testGetEntryPoint() public view {
        assertEq(accountForAA.getEntryPoint(), helperConfig.getConfig().entryPoint);
    }

    function testGetConfigByChainidWorksProperly() public {
        // Arrange
        uint256 invalidChainId = 111222333;

        // Act, Assert
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        helperConfig.getConfigByChainId(invalidChainId);
    }

    // function testScriptSendPackedUserOperation() public {
    //     // Arrange
    //     // The approval comes from the ERC4337 contract, not the EOA
    //     address erc4337 = DevOpsTools.get_most_recent_deployment("ERC4337", block.chainid);

    //     // fund the account to pay prefund
    //     vm.deal(erc4337, 1 ether);

    //     // Fund ERC4337 account with vinayToken so approval makes sense
    //     deal(helperConfig.getConfig().token, erc4337, 100 ether);

    //     // Act
    //     bundlerWork.run();

    //     // Assert allowance
    //     uint256 allowance = IERC20(helperConfig.getConfig().token).allowance(
    //         erc4337, // smart account is the owner of allowances
    //         bundlerWork.RANDOM_APPROVER()
    //     );

    //     assertEq(allowance, bundlerWork.allowanceAmount());
    // }

    function testSetWhiteList() public {
        // Arrange
        address testingAddress = makeAddr("test");
        bool allowed = true;

        // Act
        vm.prank(helperConfig.getConfig().account);
        paymaster.setWhitelist(testingAddress, allowed);

        // Assert
        assertTrue(paymaster.isWhitelisted(testingAddress));
    }

    function testSetWhiteListCanOnlyBeGrantedByOwner() public {
        // Arrange
        address nonOwner = makeAddr("nonOwner");
        address testingAddress = makeAddr("test");
        bool allowed = true;

        // Act, Assert
        vm.prank(nonOwner);
        vm.expectRevert();
        paymaster.setWhitelist(testingAddress, allowed);
    }

    function testDepositIncreasesBalance() public {
        uint256 amount = 1 ether;

        // Arrange: get balance before
        uint256 beforeBalance = entryPoint.balanceOf(address(paymaster));

        // Act: deposit
        vm.deal(address(this), amount); // give test contract ETH
        uint256 beforeCaller = address(this).balance;
        paymaster.deposit{value: amount}();

        // Assert: balance increased
        uint256 afterBalance = entryPoint.balanceOf(address(paymaster));
        uint256 afterCaller = address(this).balance;
        assertEq(afterBalance, beforeBalance + amount);
        assertEq(beforeCaller - afterCaller, amount);
    }

    function testAddStake_IncreasesStakeAndSetsDelay() public {
        uint256 amt = 1 ether;
        uint32 delay = 1 days;

        IStakeManager06.DepositInfo memory beforeInfo = entryPoint.getDepositInfo(address(paymaster));

        vm.deal(helperConfig.getConfig().account, amt);
        // uint256 balanceBeforeCheck = address(entryPoint).balance;
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: amt}(delay);
        // uint256 balanceAfterCheck = address(entryPoint).balance;

        // console.log(balanceBeforeCheck);
        // console.log(balanceAfterCheck);   // for clarity

        IStakeManager06.DepositInfo memory afterInfo = entryPoint.getDepositInfo(address(paymaster));

        assertEq(afterInfo.stake, beforeInfo.stake + uint112(amt));
        assertTrue(afterInfo.staked);
        assertEq(afterInfo.unstakeDelaySec, delay);
        assertEq(afterInfo.withdrawTime, 0);
    }

    function addStakeIsPossibleByOwnerOnly() public {
        address invalidAddress = makeAddr("invalidAddress");
        uint32 delay = 1 days;

        vm.expectRevert();
        vm.prank(invalidAddress);
        paymaster.addStake{value: 1 ether}(delay);
    }

    function testUnlockStake_SetsWithdrawTime() public {
        uint256 amt = 1 ether;
        uint32 delay = 3 days;

        vm.deal(helperConfig.getConfig().account, amt);
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: amt}(delay);

        uint48 expected = uint48(block.timestamp + delay);
        vm.prank(helperConfig.getConfig().account);
        paymaster.unlockStake();

        IStakeManager06.DepositInfo memory info = entryPoint.getDepositInfo(address(paymaster));

        assertEq(info.withdrawTime, expected);
    }

    function testWithdrawStake_AfterDelay() public {
        uint256 amt = 1 ether;
        uint32 delay = 1 days;
        address payable to = payable(address(0xBEEF));

        vm.deal(helperConfig.getConfig().account, amt);
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: amt}(delay);

        vm.prank(helperConfig.getConfig().account);
        paymaster.unlockStake();

        // Fast-forward to (or past) withdraw time
        IStakeManager06.DepositInfo memory mid = entryPoint.getDepositInfo(address(paymaster));
        vm.warp(mid.withdrawTime);

        uint256 beforeTo = to.balance;
        vm.prank(helperConfig.getConfig().account);
        paymaster.withdrawStake(to);

        IStakeManager06.DepositInfo memory afterInfo = entryPoint.getDepositInfo(address(paymaster));

        assertEq(afterInfo.stake, 0);
        assertFalse(afterInfo.staked);
        assertEq(to.balance, beforeTo + amt);
    }

    function testWithdrawTo_FromDeposit() public {
        uint256 amt = 1 ether;
        address payable to = payable(address(0xCAFE));

        vm.deal(helperConfig.getConfig().account, amt);
        paymaster.deposit{value: amt}();

        uint256 beforeDep = entryPoint.balanceOf(address(paymaster));
        uint256 beforeTo = to.balance;

        vm.prank(helperConfig.getConfig().account);
        paymaster.withdrawDeposits(to, 0.4 ether);

        uint256 afterDep = entryPoint.balanceOf(address(paymaster));
        assertEq(afterDep, beforeDep - 0.4 ether);
        assertEq(to.balance, beforeTo + 0.4 ether);
    }

    function testValidationPaymasterUserOp() public {
        // 1. create dummy owner with a dummy private key
        (address dummyOwner, uint256 dummyPk) = makeAddrAndKey("dummyOwnerForTesting");

        // 2. deploy a fresh ERC4337 account with dummyOwner as the owner
        vm.prank(dummyOwner);
        ERC4337 account = new ERC4337(address(entryPoint));

        address someSpender = makeAddr("someSpender");
        // 1. fetch nonce from EntryPoint
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(account), 0);

        // 2. Adding whitelist so that paymaster can pay
        vm.prank(helperConfig.getConfig().account);
        paymaster.setWhitelist(address(account), true);

        // 3. Stake + Deposit
        vm.deal(helperConfig.getConfig().account, 5 ether);
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: 1 ether}(1 days);

        vm.prank(helperConfig.getConfig().account);
        paymaster.deposit{value: 2 ether}();

        // Arrange
        // 3. build the UserOp
        UserOperation06 memory userOp = UserOperation06({
            sender: address(account),
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeWithSelector(
                ERC4337.execute.selector,
                helperConfig.getConfig().token,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, someSpender, 1e18)
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: hex""
        });

        // 5. get userOpHash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // 6. sign with dummy private key
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dummyPk, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // Act
        // 8. validate userOp
        uint256 missingAccountFunds = userOp.preVerificationGas * userOp.maxFeePerGas;
        vm.prank(address(entryPoint)); // only EntryPoint can call
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(userOp, userOpHash, missingAccountFunds);

        ops.push(userOp);

        address bundler = makeAddr("bundler");

        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        // Assert
        assertEq(validationData, SIG_VALIDATION_SUCCESS); // SIG_VALIDATION_SUCCESS = 0
        uint256 allowance = IERC20(helperConfig.getConfig().token).allowance(address(account), someSpender);
        assertEq(allowance, 1e18);
    }

    function testValidationPaymasterUserOpFailedIfAddressNotWhiteListed() public {
        // 1. create dummy owner with a dummy private key
        (address dummyOwner, uint256 dummyPk) = makeAddrAndKey("dummyOwnerForTesting");

        // 2. deploy a fresh ERC4337 account with dummyOwner as the owner
        vm.prank(dummyOwner);
        ERC4337 account = new ERC4337(address(entryPoint));

        address someSpender = makeAddr("someSpender");
        // 1. fetch nonce from EntryPoint
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(account), 0);

        // 2. Adding whitelist so that paymaster can pay
        // paymaster.setWhitelist(address(account), true); //Here i will check if i will not allow whitelist i will get 1 in result which means failed

        // 3. Stake + Deposit
        vm.deal(helperConfig.getConfig().account, 5 ether);
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: 1 ether}(1 days);

        vm.prank(helperConfig.getConfig().account);
        paymaster.deposit{value: 2 ether}();

        // Arrange
        // 3. build the UserOp
        UserOperation06 memory userOp = UserOperation06({
            sender: address(account),
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeWithSelector(
                ERC4337.execute.selector,
                helperConfig.getConfig().token,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, someSpender, 1e18)
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: hex""
        });

        // 5. get userOpHash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // 6. sign with dummy private key
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dummyPk, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // Act
        // 8. validate userOp
        uint256 missingAccountFunds = userOp.preVerificationGas * userOp.maxFeePerGas;
        vm.prank(address(entryPoint)); // only EntryPoint can call
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(userOp, userOpHash, missingAccountFunds);

        // Assert
        //Failed because i havent set whitelist
        assertEq(validationData, SIG_VALIDATION_FAILED); // SIG_VALIDATION_FAILED = 1
    }

    function testValidationPaymasterUserOpCanBePassedOnlyByEntryPoint() public {
        // 1. create dummy owner with a dummy private key
        (address dummyOwner, uint256 dummyPk) = makeAddrAndKey("dummyOwnerForTesting");

        // 2. deploy a fresh ERC4337 account with dummyOwner as the owner
        vm.prank(dummyOwner);
        ERC4337 account = new ERC4337(address(entryPoint));

        address someSpender = makeAddr("someSpender");
        // 1. fetch nonce from EntryPoint
        uint256 nonce = INonceManager06(address(entryPoint)).getNonce(address(account), 0);

        // 2. Adding whitelist so that paymaster can pay
        vm.prank(helperConfig.getConfig().account);
        paymaster.setWhitelist(address(account), true); //Here i will check if i will not allow whitelist i will get 1 in result which means failed

        // 3. Stake + Deposit
        vm.deal(helperConfig.getConfig().account, 5 ether);
        vm.prank(helperConfig.getConfig().account);
        paymaster.addStake{value: 1 ether}(1 days);

        vm.prank(helperConfig.getConfig().account);
        paymaster.deposit{value: 2 ether}();

        // Arrange
        // 3. build the UserOp
        UserOperation06 memory userOp = UserOperation06({
            sender: address(account),
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeWithSelector(
                ERC4337.execute.selector,
                helperConfig.getConfig().token,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, someSpender, 1e18)
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: hex""
        });

        // 5. get userOpHash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // 6. sign with dummy private key
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(dummyPk, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // Act
        // 8. validate userOp
        uint256 missingAccountFunds = userOp.preVerificationGas * userOp.maxFeePerGas;

        address invalidAddress = makeAddr("invalidAddress");
        vm.prank(invalidAddress); // only EntryPoint can call
        vm.expectRevert(SimpleWhitelistPaymaster06.SimpleWhitelistPaymaster06__NotEntryPoint.selector);
        paymaster.validatePaymasterUserOp(userOp, userOpHash, missingAccountFunds);
    }

    function testPostOpCanBeCalledByOnlyEntryPoint() public {
        // Arrange
        bytes memory context;
        uint256 gasCost = 1e9;

        // Act + Assert
        vm.expectRevert(SimpleWhitelistPaymaster06.SimpleWhitelistPaymaster06__NotEntryPoint.selector);

        vm.prank(makeAddr("attacker")); // not entryPoint
        paymaster.postOp(
            IPaymaster06.PostOpMode.opSucceeded, // can also pass PostOpMode(0)
            context,
            gasCost
        );
    }

    // function testSendPackedUserOperationViaPaymaster() public {
    //     // Arrange
    //     // The approval comes from the ERC4337 contract, not the EOA
    //     uint32 unstakeDelaySec = 1 days;
    //     address erc4337 = DevOpsTools.get_most_recent_deployment("ERC4337", block.chainid);
    //     address paymasterWork = DevOpsTools.get_most_recent_deployment("SimpleWhitelistPaymaster06", block.chainid);

    //     // fund the account to pay prefund
    //     vm.deal(helperConfig.getConfig().account, 10 ether);
    //     vm.prank(helperConfig.getConfig().account);
    //     SimpleWhitelistPaymaster06(paymasterWork).setWhitelist(erc4337, true);

    //     vm.prank(helperConfig.getConfig().account);
    //     SimpleWhitelistPaymaster06(paymasterWork).deposit{value: 1 ether}();

    //     vm.prank(helperConfig.getConfig().account);
    //     SimpleWhitelistPaymaster06(paymasterWork).addStake{value: 1 ether}(unstakeDelaySec);

    //     // Fund ERC4337 account with vinayToken so approval makes sense
    //     deal(helperConfig.getConfig().token, erc4337, 100 ether);

    //     // Act
    //     bundlerWork2.run();

    //     // Assert allowance
    //     uint256 allowance = IERC20(helperConfig.getConfig().token).allowance(
    //         erc4337, // smart account is the owner of allowances
    //         bundlerWork.RANDOM_APPROVER()
    //     );

    //     assertEq(allowance, bundlerWork.allowanceAmount());
    // }
}

// import {Test, console2} from "forge-std/Test.sol";
// import {HelperConfig} from "../script/HelperConfig.s.sol";
// import {SignedPackedUSerOperations, UserOperation06, IEntryPoint} from "../script/signedPackedUserOperations.s.sol";
// import {UserOperation06} from "lib/account-abstraction/contracts/legacy/v06/UserOperation06.sol";
// import {ERC4337} from "../src/EIP_4337_AA.sol";
// import {DeployERC4337} from "../script/EIP4337AA.s.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {Token} from "../src/Token.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// contract EIP4337Test is Test {
//     using MessageHashUtils for bytes32;

//     ERC4337 acc;
//     HelperConfig config;
//     Token usdc;
//     SignedPackedUSerOperations userOp;

//     uint256 public constant AMOUNT = 1e18;

//     function setUp() public {
//         DeployERC4337 deployer = new DeployERC4337();
//         (config, acc) = deployer.run();
//         usdc = new Token();
//         userOp = new SignedPackedUSerOperations();
//     }

//     function test_Mint() public {
//         assertEq(usdc.balanceOf(address(acc)), 0);
//         address dest = address(usdc);
//         uint256 value = 0;
//         bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);

//         address entryPoint = acc.getEntryPoint();
//         vm.prank(entryPoint);
//         acc.execute(dest, value, callData);

//         assertEq(usdc.balanceOf(address(acc)), 1e18);
//     }

//     function test_MintNonEntrypoint() public {
//         assertEq(usdc.balanceOf(address(acc)), 0);
//         address dest = address(usdc);
//         uint256 value = 0;
//         bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);

//         address user = makeAddr("user");
//         vm.prank(user);
//         vm.expectRevert(ERC4337.ERC4337__NotFromEntryPointOrOwner.selector);
//         acc.execute(dest, value, callData);

//         assertEq(usdc.balanceOf(address(acc)), 0);
//     }

//     function test_Signature() public {
//         address dest = address(usdc);
//         uint256 value = 0;
//         bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
//         bytes memory executeData = abi.encodeWithSelector(ERC4337.execute.selector, dest, value, callData);

//         UserOperation06 memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));

//         bytes32 hash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(op);
//         address signatory = ECDSA.recover(hash.toEthSignedMessageHash(), op.signature);

//         assertEq(signatory, acc.owner());
//     }

//     function test_validateUserOp() public {
//         address dest = address(usdc);
//         uint256 value = 0;
//         bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
//         bytes memory executeData = abi.encodeWithSelector(ERC4337.execute.selector, dest, value, callData);

//         UserOperation06 memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));
//         // PackedUserOperation memory packedOp = PackedUserOperation(
//         //     op.sender,
//         //     op.nonce,
//         //     op.initCode,
//         //     op.callData,
//         //     op.accountGasLimits,
//         //     op.preVerificationGas,
//         //     op.gasFees,
//         //     op.paymasterAndData,
//         //     op.signature
//         // );
//         bytes32 userOperationHash = IEntryPoint(config.getConfig().entryPoint).getUserOpHash(op);

//         uint256 missingAccountFunds = 1e18;
//         vm.deal(address(acc), 2e18);
//         vm.prank(config.getConfig().entryPoint);
//         uint256 ok = acc.validateUserOp(op, userOperationHash, missingAccountFunds);
//         assertEq(ok, 0);
//     }

//     function test_EntrypointExecute() public {
//         uint256 balanceBefore = config.getConfig().entryPoint.balance;
//         address user = makeAddr("user");
//         assertEq(usdc.balanceOf(address(acc)), 0);
//         address dest = address(usdc);
//         uint256 value = 0;
//         bytes memory callData = abi.encodeWithSelector(Token.mint.selector, address(acc), AMOUNT);
//         bytes memory executeData = abi.encodeWithSelector(ERC4337.execute.selector, dest, value, callData);

//         UserOperation06 memory op = userOp.generateSignedUserOperation(executeData, config.getConfig(), address(acc));

//         vm.deal(address(acc), 0.03 ether);

//         UserOperation06[] memory ops = new UserOperation06[](1);
//         ops[0] = op;

//         vm.prank(user);
//         IEntryPoint(config.getConfig().entryPoint).handleOps(ops, payable(user));
//         assertEq(usdc.balanceOf(address(acc)), 1e18);
//         uint256 balanceAfter = config.getConfig().entryPoint.balance;
//         console2.log("the balance of entry point contract is", balanceAfter - balanceBefore);
//         console2.log("the remaining amount in acc: ", address(acc).balance);
//         console2.log("the original balance of the account is:", address(acc).balance + (balanceAfter - balanceBefore));
//     }
// }
