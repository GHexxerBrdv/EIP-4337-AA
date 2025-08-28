// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/legacy/v06/IEntryPoint06.sol";
import {IPaymaster06} from "lib/account-abstraction/contracts/legacy/v06/IPaymaster06.sol";
import {UserOperation06} from "lib/account-abstraction/contracts/legacy/v06/UserOperation06.sol";

contract PaymasterEIP4337 is IPaymaster06, Ownable {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    error PaymasterEIP4337__MustBeEntryPoint();
    error PaymasterEIP4337__SponserShipLimitExeed(uint256 maxCost, uint256 maxSponsorship);
    error PaymasterEIP4337__NotEnoughBalance();
    error PaymasterEIP4337__TransactionFailed();
    error PaymasterEIP4337__InsufficientDeposit(address paymaster, uint256 maxCost);
    error PaymasterEIP4337__ZeroAddress();
    error PaymasterEIP4337__ZeroAmount();

    IEntryPoint public immutable i_entryPoint;
    uint256 public maxSponsorship;

    mapping(address => uint256) public sponsoredOperations;
    mapping(address => uint256) public totalSponsordGas;

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

    function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        view
        onlyEntrypoint
        returns (bytes memory context, uint256 validationData)
    {
        if (i_entryPoint.balanceOf(address(this)) < maxCost) {
            revert PaymasterEIP4337__InsufficientDeposit(address(this), maxCost);
        }

        if (maxCost > maxSponsorship) {
            revert PaymasterEIP4337__SponserShipLimitExeed(maxCost, maxSponsorship);
        }

        validationData = _verifySignature(userOp, userOpHash);
        context = abi.encodePacked(userOp.sender);
    }

    function postOp(PostOpMode, /*mode*/ bytes calldata context, uint256 actualGasCost) external onlyEntrypoint {
        address account = address(bytes20(context[0:20]));

        sponsoredOperations[account]++;
        totalSponsordGas[account] = actualGasCost;
    }

    function changeSponsorShip(uint256 sponsorShip) external onlyOwner {
        maxSponsorship = sponsorShip;
        emit ChangedSponserShip(sponsorShip);
    }

    function depositToEntryPoint(uint256 amount) external payable onlyOwner {
        if (amount == 0) {
            revert PaymasterEIP4337__ZeroAmount();
        }

        if (msg.value == 0) {
            if (address(this).balance < amount) {
                revert PaymasterEIP4337__NotEnoughBalance();
            }

            i_entryPoint.depositTo{value: amount}(address(this));
        } else {
            i_entryPoint.depositTo{value: msg.value}(address(this));
        }
    }

    function withdrawEth(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert PaymasterEIP4337__ZeroAddress();
        }

        if (amount == 0) {
            revert PaymasterEIP4337__ZeroAmount();
        }

        if (amount > address(this).balance) {
            revert PaymasterEIP4337__NotEnoughBalance();
        }

        (bool ok,) = to.call{value: amount}("");
        if (!ok) {
            revert PaymasterEIP4337__TransactionFailed();
        }
    }

    function withdrawFromEntryPoint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert PaymasterEIP4337__ZeroAddress();
        }
        if (amount == 0) {
            revert PaymasterEIP4337__ZeroAmount();
        }

        i_entryPoint.withdrawTo(payable(to), amount);
    }

    function _verifySignature(UserOperation06 memory userOp, bytes32 userOpHash) internal pure returns (uint256) {
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address signatory = ethHash.recover(userOp.signature);
        if (signatory != userOp.sender) {
            return 1;
        }
        return 0;
    }
}
