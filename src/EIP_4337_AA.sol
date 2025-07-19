// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
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

    function _verifySignature(PackedUserOperation memory userOp, bytes32 userOpHash) internal view returns (uint256) {
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address signatory = ethHash.recover(userOp.signature);
        if (signatory != owner()) {
            return 1;
        }
        return 0;
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
