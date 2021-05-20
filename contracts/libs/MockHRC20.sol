// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./token/HRC20/HRC20.sol";

contract MockHRC20 is HRC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public HRC20(name, symbol) {
        _mint(msg.sender, supply);

    }
}