// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("test", "test") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
