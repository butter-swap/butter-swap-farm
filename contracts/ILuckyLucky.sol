//SPDX-License-Identifier: MIT
pragma solidity >= 0.6.0 < 0.8.0;

interface ILuckyLucky {

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------

    // function getMaxRange() external view returns(uint32);

    //-------------------------------------------------------------------------
    // STATE MODIFYING FUNCTIONS 
    //-------------------------------------------------------------------------

    function numbersDrawn(
        uint256 _luckyId,
        bytes32 _requestId, 
        uint256 _randomNumber
    ) 
        external;
}