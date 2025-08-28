// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// v0.6 (legacy) interfaces
import {IEntryPoint} from "lib/account-abstraction/contracts/legacy/v06/IEntryPoint06.sol";
import {IPaymaster06} from "lib/account-abstraction/contracts/legacy/v06/IPaymaster06.sol";
import {UserOperation06} from "lib/account-abstraction/contracts/legacy/v06/UserOperation06.sol";

/**
 * @title SimpleWhitelistPaymaster06
 * @notice Minimal ETH-sponsored paymaster for EntryPoint v0.6
 * - Stake + deposit ETH into EntryPoint
 * - Whitelist which accounts it will sponsor
 * - No ERC20 logic (you can add later)
 */
contract SimpleWhitelistPaymaster06 is IPaymaster06, Ownable {
    error SimpleWhitelistPaymaster06__NotEntryPoint();

    IEntryPoint public immutable entryPoint;

    mapping(address => bool) public isWhitelisted;

    constructor(address _entryPoint) Ownable(msg.sender) {
        entryPoint = IEntryPoint(_entryPoint);
    }

    /* -------------------- Admin -------------------- */

    function setWhitelist(address account, bool allowed) external onlyOwner {
        isWhitelisted[account] = allowed;
    }

    /// @notice deposit ETH used to pay for userOps (prefund)
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice stake for validation (required for paymasters)
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    function withdrawStake(address payable to) external onlyOwner {
        entryPoint.withdrawStake(to);
    }

    function withdrawDeposits(address payable to, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(to, amount);
    }

    /* ----------------- IPaymaster (v0.6) ----------------- */

    /**
     * @dev EntryPoint calls this during validation. Must return (context, validationData).
     * validationData:
     *   - 0 => success
     *   - nonzero (e.g., 1) => signature/validation failed (EP will drop the op)
     */
    function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, /*userOpHash*/ uint256 /*maxCost*/ )
        external
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        if (msg.sender != address(entryPoint)) revert SimpleWhitelistPaymaster06__NotEntryPoint();

        // simple rule: only sponsor whitelisted senders
        if (!isWhitelisted[userOp.sender]) {
            // non-zero validationData => EP treats as validation failure (no revert)
            return ("", 1);
        }

        // if you want to pass info to postOp, encode it in context:
        context = abi.encode(userOp.sender);
        validationData = 0; // success
    }

    /**
     * @dev Called by EntryPoint after the call, to settle payment or accounting.
     * We’re not charging the user; just emit an event.
     */
    function postOp(PostOpMode, /*mode*/ bytes calldata, /*context*/ uint256 /*actualGasCost*/ )
        external
        view
        override
    {
        if (msg.sender != address(entryPoint)) revert SimpleWhitelistPaymaster06__NotEntryPoint();
        // no-op for minimal paymaster
    }
}
