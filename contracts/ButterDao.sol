// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/math/SafeMath.sol";
import "./libs/token/HRC20/IHRC20.sol";
import "./libs/token/HRC20/SafeHRC20.sol";
import "./libs/access/Ownable.sol";

import "./ButterToken.sol";
import "./CreamToken.sol";
import "./DAOToken.sol";
import "./BoardToken.sol";

contract ButterDao is Ownable {
    uint256 constant DAY_IN_SECONDS = 86400;
    uint256 constant WEEK_IN_SECONDS = 604800;

    using SafeMath for uint256;
    using SafeHRC20 for IHRC20;

    // The Butter TOKEN
    IHRC20 public butter;
    // The Cream TOKEN
    IHRC20 public cream;
    // dao token
    DAOToken public daoToken;
    // board token
    BoardToken public boardToken;

    // if conditionTurnOn, when user leave stake, have to check whether staked after seven days and is Sunday
    bool public conditionTurnOn = false;
    // threshold ratio
    uint256 public thresholdDivider = 1000;

    struct UserInfo {
        uint256 amount; // How many Cream tokens the user has provided.
        uint256 stakeTs; // block timestamp the last time user become board member
    }

    // Info of each user that stakes Cream tokens.
    mapping(address => UserInfo) public userInfo;
    // dao members
    mapping(address => bool) public daoMembers;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        ButterToken _butter,
        CreamToken _cream,
        DAOToken _daoToken,
        BoardToken _boardToken,
        bool _turnOnCondition
    ) public {
        butter = _butter;
        cream = _cream;
        daoToken = _daoToken;
        boardToken = _boardToken;
        conditionTurnOn = _turnOnCondition;
    }

    function switchCondition(bool _turnOn) external onlyOwner {
        conditionTurnOn = _turnOn;
    }

    function changeThresholdDivider(uint256 _thresholdDivider)
        public
        onlyOwner
    {
        thresholdDivider = _thresholdDivider;
    }

    // Stake Cream tokens for dao token
    function enterStake(uint256 _amount) external {
        require(_amount > 0, "enterStake: amount should be large than 0");

        // if already dao member, directly add amount
        if (daoMembers[msg.sender]) {
            UserInfo storage user = userInfo[msg.sender];
            user.amount = user.amount.add(_amount);

            cream.safeTransferFrom(address(msg.sender), address(this), _amount);
            daoToken.mint(msg.sender, _amount);
            boardToken.mint(msg.sender, _amount);
        } else {
            // check condition
            // staked amount should be larger than 0.1% of butter total supply at the first time
            uint256 butterTotal = butter.totalSupply();
            uint256 burned =
                butter.balanceOf(
                    address(0x000000000000000000000000000000000000dEaD)
                );
            uint256 validTotal = butterTotal.sub(burned);
            uint256 threshold =
                validTotal.div(thresholdDivider).div(10**18 * 1000).mul(
                    10**18 * 1000
                );
            require(
                _amount >= threshold,
                "enterStake: staked amount should not be less than threshold ratio of total butter valid supply for the first time"
            );

            UserInfo storage user = userInfo[msg.sender];
            user.amount = user.amount.add(_amount);
            user.stakeTs = block.timestamp;
            daoMembers[msg.sender] = true;

            cream.safeTransferFrom(address(msg.sender), address(this), _amount);
            daoToken.mint(msg.sender, _amount);
            boardToken.mint(msg.sender, _amount);
        }

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw Cream tokens from STAKING.
    function leaveStake() external {
        require(
            daoMembers[msg.sender],
            "leaveStake: you are not dao member"
        );

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "leaveStake: staked balance zero");
        uint256 daoHoldAmount = daoToken.balanceOf(address(msg.sender));
        uint256 boardHoldAmount = boardToken.balanceOf(address(msg.sender));
        require(
            daoHoldAmount >= user.amount,
            "leaveStake: dao token balance is less than marked balance, have you transferred?"
        );
        require(
            boardHoldAmount >= user.amount,
            "leaveStake: board token balance is less than marked balance, have you transferred?"
        );

        if (conditionTurnOn) {
            require(
                block.timestamp - user.stakeTs >= WEEK_IN_SECONDS,
                "leaveStake: leave stake only after seven days"
            );

            // check sunday
            require(
                isSunday(block.timestamp),
                "leaveStake: leave stake only when Sunday(UTC+8)"
            );
        }

        uint256 userAmount = user.amount;
        user.amount = 0;
        daoMembers[msg.sender] = false;

        safeCreamTransfer(address(msg.sender), userAmount);
        daoToken.burn(msg.sender, userAmount);
        boardToken.burn(msg.sender, userAmount);

        emit Withdraw(msg.sender, userAmount);
    }

    // first time stake threshold
    function firstStakeThreshold() external view returns (uint256) {
        // staked amount should be larger than 1/thresholdDivider of butter total supply at the first time
        uint256 butterTotal = butter.totalSupply();
        uint256 burned =
            butter.balanceOf(
                address(0x000000000000000000000000000000000000dEaD)
            );
        uint256 validTotal = butterTotal.sub(burned);
        uint256 threshold =
            validTotal.div(thresholdDivider).div(10**18 * 1000).mul(
                10**18 * 1000
            );

        return threshold;
    }

    // precheck before leave STAKING.
    function leaveStakePrecheck() external view returns (bool) {
        if (!daoMembers[msg.sender]) {
            return false;
        }

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) {
            return false;
        }

        uint256 daoHoldAmount = daoToken.balanceOf(address(msg.sender));
        uint256 boardHoldAmount = boardToken.balanceOf(address(msg.sender));
        if (daoHoldAmount < user.amount) {
            return false;
        }
        if (boardHoldAmount < user.amount) {
            return false;
        }

        if (conditionTurnOn) {
            if (block.timestamp - user.stakeTs < WEEK_IN_SECONDS) {
                return false;
            }

            // check sunday
            if (isSunday(block.timestamp)) {
                return true;
            } else {
                return false;
            }
        } else {
            return true;
        }
    }

    function isSunday(uint256 _ts) private pure returns (bool) {
        uint256 baseTs = 1624118400; // 2021-06-20 00:00:00 utc+8 sunday
        if (_ts.sub(baseTs).div(DAY_IN_SECONDS).mod(7) == 0) {
            return true;
        }
        return false;
    }

    // Safe cream transfer function, just in case if rounding error causes pool to not have enough Cream.
    function safeCreamTransfer(address _to, uint256 _amount) private {
        uint256 creamBal = cream.balanceOf(address(this));
        if (_amount > creamBal) {
            cream.safeTransfer(_to, creamBal);
        } else {
            cream.safeTransfer(_to, _amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "emergencyWithdraw: staked balance zero");
        require(
            user.amount >= _amount,
            "emergencyWithdraw: left user amount is less than required amount"
        );

        if (conditionTurnOn) {
            require(
                block.timestamp - user.stakeTs >= WEEK_IN_SECONDS,
                "emergencyWithdraw: leave stake only after seven days"
            );

            // check sunday
            require(
                isSunday(block.timestamp),
                "emergencyWithdraw: leave stake only when Sunday(UTC+8)"
            );
        }

        user.amount = user.amount.sub(_amount);
        daoMembers[msg.sender] = false;

        safeCreamTransfer(address(msg.sender), _amount);
        daoToken.burn(msg.sender, _amount);
        boardToken.burn(msg.sender, _amount);

        emit EmergencyWithdraw(msg.sender, _amount);
    }
}
