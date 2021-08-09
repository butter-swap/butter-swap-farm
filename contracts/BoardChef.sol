// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './libs/math/SafeMath.sol';
import './libs/token/HRC20/IHRC20.sol';
import './libs/token/HRC20/SafeHRC20.sol';
import './libs/access/Ownable.sol';
import './IButterDao.sol';

// deposit board token for other tokens
contract BoardChef is Ownable {
    using SafeMath for uint256;
    using SafeHRC20 for IHRC20;

    // Info of each user
    struct UserInfo {
        uint256 amount;     // How many board token tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of board tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws board token tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 lastRewardBlock;  // Last block number that Reward Token distribution occurs.
        uint256 accRewardPerShare; // Accumulated Reward Token per share, times 1e12. See below.
    }

    // The board TOKEN
    IHRC20 public boardToken;
    IHRC20 public rewardToken;

    IButterDao public immutable butterDao;

    // reward per block.
    uint256 public rewardPerBlock;

    // Info of pool
    PoolInfo public poolInfo;
    // Info of each user that stakes board tokens.
    mapping (address => UserInfo) public userInfo;
    
    // The block number when reward token starts.
    uint256 public startBlock;
    // The block number when reward tokens ends.
    uint256 public bonusEndBlock;

    uint256 public requiredBoardLevel;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IHRC20 _boardToken,
        IHRC20 _rewardToken,
        IButterDao _butterDao,
        uint256 _requiredBoardLevel,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        boardToken = _boardToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        butterDao = _butterDao;
        requiredBoardLevel = _requiredBoardLevel;

        // staking pool
        poolInfo = PoolInfo({
            lastRewardBlock: startBlock,
            accRewardPerShare: 0
        });
    }

    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        uint256 totalSupply = boardToken.balanceOf(address(this));
        if (block.number > poolInfo.lastRewardBlock && totalSupply != 0) {
            uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock);
            accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(totalSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        uint256 totalSupply = boardToken.balanceOf(address(this));
        if (totalSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock);

        poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(tokenReward.mul(1e12).div(totalSupply));
        poolInfo.lastRewardBlock = block.number;
    }

    // Stake board tokens to BoardChef for Reward allocation
    function deposit(uint256 _amount) external {
        require (_amount >= 0, 'amount less than 0');
        (uint256 amount, uint256 stakeTs, uint256 boardLevel) = IButterDao(butterDao).userInfo(address(msg.sender));
        require(boardLevel >= requiredBoardLevel, "required board level not exceed");
        UserInfo storage user = userInfo[msg.sender];
        updatePool();

        uint256 pending = 0;
        if (user.amount > 0) {
            pending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        }
        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if (_amount > 0) {
            boardToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw board tokens from STAKING.
    function withdraw(uint256 _amount) external {
        require (_amount >= 0, 'amount less than 0');
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not enough");

        updatePool();
        uint256 pending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        if(pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if(_amount > 0) {
            boardToken.safeTransfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        boardToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

}
