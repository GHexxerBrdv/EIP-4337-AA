// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {UserOperation} from "account-abstraction/interfaces/UserOperation.sol";
// import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IAccount} from "./Helper/IAccount.sol";
import {IEntryPoint} from "./Helper/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// import {console2} from "forge-std/Script.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

contract EIP4337AA is IAccount, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error EIP4337AA__NotFromEntryPoint();
    error EIP4337AA__InvalidSigner();
    error EIP4337AA__ExecutionFailed();

    IEntryPoint private immutable i_entryPoint;

    receive() external payable {}

    modifier onlyEntryPoint() {
        require(msg.sender == address(i_entryPoint), EIP4337AA__NotFromEntryPoint());
        _;
    }

    constructor(address _entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
    }

    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        onlyEntryPoint
        returns (uint256 validationData)
    {
        validationData = _verifySignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    function _payPrefund(uint256 amount) internal {
        if (amount != 0) {
            (bool ok,) = msg.sender.call{value: amount}("");
            (ok);
        }
    }

    function _verifySignature(UserOperation memory userOp, bytes32 userOpHash) internal view returns (uint256) {
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address signatory = ethHash.recover(userOp.signature);

        if (signatory != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function execute(address dest, uint256 amount, bytes calldata data) external onlyEntryPoint {
        (bool ok,) = dest.call{value: amount}(data);

        if (!ok) {
            revert EIP4337AA__ExecutionFailed();
        }
    }

    function getEntryPint() external view returns (address) {
        return address(i_entryPoint);
    }
}
