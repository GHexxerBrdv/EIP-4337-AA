// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {IAccount, PackedUserOperation} from "account-abstraction/interfaces/IAccount.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PaymasterEIP4337 is IPaymaster, Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    error PaymasterEIP4337__MustBeEntryPoint();
    error PaymasterEIP4337__SponserShipLimitExeed(uint256 maxCost, uint256 maxSponsorship);
    error PaymasterEIP4337__NotEnoughBalance();
    error PaymasterEIP4337__TransactionFailed();
    error PaymasterEIP4337__InsufficientDeposit(address paymaster, uint256 maxCost);

    IEntryPoint private immutable i_entryPoint;
    uint256 private maxSponsorship;

    event ChangedSponserShip(uint256 newSponsorship);

    constructor(address _entryPoint, uint256 sponsorShip) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
        maxSponsorship = sponsorShip;
    }

    modifier onlyEntrypoint() {
        require(msg.sender == address(i_entryPoint), PaymasterEIP4337__MustBeEntryPoint());
        _;
    }

    receive() external payable {}

    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        onlyEntrypoint
        returns (bytes memory context, uint256 validationData)
    {
        if (i_entryPoint.balanceOf(address(this)) < maxCost) {
            revert PaymasterEIP4337__InsufficientDeposit(address(this), maxCost);
        }

        if (maxCost > maxSponsorship) {
            revert PaymasterEIP4337__SponserShipLimitExeed(maxCost, maxSponsorship);
        }

        context = "";
        validationData = 0;
    }

    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external
        onlyEntrypoint
    {}

    function changeSponsorShip(uint256 sponsorShip) external onlyOwner {
        maxSponsorship = sponsorShip;
        emit ChangedSponserShip(sponsorShip);
    }

    function depositToEntryPoint(uint256 amount) external onlyOwner {
        if(address(this).balance > amount) {
            revert PaymasterEIP4337__NotEnoughBalance();
        }

        i_entryPoint.depositTo{value: amount}(address(this));
    }

    function withdrawEth(address to, uint256 amount) external onlyOwner {
        if(amount > address(this).balance) {
            revert PaymasterEIP4337__NotEnoughBalance();
        }

        (bool ok,) = to.call{value: amount}("");
        if(!ok) {
            revert PaymasterEIP4337__TransactionFailed();
        }
    }   
}
