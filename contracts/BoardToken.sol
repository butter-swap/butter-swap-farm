// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/token/HRC20/HRC20.sol";

// BoardToken for pool.
contract BoardToken is HRC20("Butter Board Token", "BOARD") {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (ButterDao).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }
}
