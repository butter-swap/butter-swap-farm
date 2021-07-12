// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IButterDao {
    function daoMembers(address user) external returns (bool);
}
