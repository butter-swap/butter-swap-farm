// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './libs/math/SafeMath.sol';
import './libs/token/HRC20/IHRC20.sol';
import './libs/token/HRC20/SafeHRC20.sol';
import './libs/access/Ownable.sol';
import './ILuckyLucky.sol';
// Allows for intergration with ChainLink VRF
import "./IRandomNumberGenerator.sol";

// deposit cream for other tokens
contract LuckyLuckyChef is Ownable, ILuckyLucky {
    using SafeMath for uint256;
    using SafeHRC20 for IHRC20;

    // Info of each user
    struct UserInfo {
        uint256 amount;     // How many Board tokens the user has provided.
        uint256 power;      // The power of this user to win the prize
        bool init;
    }

    // The Board TOKEN
    IHRC20 public board;
    // The reward Token, basicly Butter
    IHRC20 public rewardToken;

    // The address to control start or end a luckylucky
    address public admin;

    // reward per peroid.
    uint256 public rewardPerPeriod;

    // Info of each user that stakes Board tokens.
    mapping (address => UserInfo) public userInfo;

    // Addresses that stake Board tokens
    address[] public userAddresses;
    
    // The block number when reward token starts.
    uint256 public startBlock;
    // The block number when reward tokens ends.
    uint256 public endBlock;

     // Storing of the randomness generator 
    IRandomNumberGenerator internal randomGenerator_;

    // the luckylucky counters 
    uint256 private luckyIdCounter_;
    // Request ID for random number
    bytes32 internal requestId_;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event LuckyOpen(uint256 luckyAmount);
    event LuckyCompleted(uint256 luckyId, uint256 luckyAmount, address luckyAddress);
    event RequestNumbers(uint256 totalPower, bytes32 requestId);

    // Represents the status of the luckylucky
    enum Status { 
        Open,           // The luckylucky is open 
        Closed,         // The luckylucky is closed and reward not sent 
        Completed       // The luckylucky has been closed and the prize has been sent
    }

    Status public status;

    // historical LuckyLucky info
    struct LuckyInfo{
        uint256 luckyId;
        uint256 rewardAmount;
        address luckyluckyWinner;
        uint256 startBlock;
        uint256 endBlock; 
    }

    // historical LuckyLucky infos
    mapping (uint256 => LuckyInfo) internal allLuckies_;

    /*
     * from "@openzeppelin/contracts/proxy/Initializable.sol";
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /*
     * from "@openzeppelin/contracts/proxy/Initializable.sol";
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !Address.isContract(address(this));
    }

    //-------------------------------------------------------------------------
    // MODIFIERS
    //-------------------------------------------------------------------------

    modifier onlyRandomGenerator() {
        require(
            msg.sender == address(randomGenerator_),
            "Only random generator"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            msg.sender == admin,
            "Only admin has permit!"
        );
        _;
    }

    /*
     * from "@openzeppelin/contracts/proxy/Initializable.sol";
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    constructor(
        IHRC20 _board,
        IHRC20 _rewardToken,
        address _admin
    ) public {
        board = _board;
        rewardToken = _rewardToken;
        status = Status.Completed;
        admin = _admin;
    }

    // for vrf reserved, expecting support heco-chain :(
    function initialize(
        address _IRandomNumberGenerator
    ) 
        external 
        initializer
        onlyOwner() 
    {
        require(
            _IRandomNumberGenerator != address(0),
            "Contracts cannot be 0 address"
        );
        randomGenerator_ = IRandomNumberGenerator(_IRandomNumberGenerator);
    }

    // set Admin address
    function setAdmin(address _admin) public onlyOwner(){
        admin = _admin;
    }

    // update the reward token amount for every period
    function updateRewardPerPeriod(uint256 _rewardPerPeriod) public onlyOwner(){
        rewardPerPeriod = _rewardPerPeriod;
    }

    // withdraw some token to owner
    function withdrawRewardToken(uint256 _amount) public onlyOwner(){
        rewardToken.safeTransfer(msg.sender, _amount);
    }

    // 获取luckylucky的总历史期数
    function getTotalLuckyLuckys() public view returns(uint256 times){
        times = luckyIdCounter_;
    }

    // get historical Lucky Info
    function getBasicLuckyInfo(uint256 _luckyId) external view returns(
        address lucky, uint256 amount, uint256 start, uint256 end
    )
    {
        LuckyInfo memory luckyInfo = allLuckies_[_luckyId];
        lucky = luckyInfo.luckyluckyWinner;
        amount = luckyInfo.rewardAmount;
        start = luckyInfo.startBlock;
        end = luckyInfo.endBlock;
    }

    /**
        Lucky-Lucky related methods
        We random a lucky user to win all rewards every Lucky-Lucky pool period.
        Every user(address) has two important factor to increase the probability:
        The Locked Board amount and the locked time. They generate the `power` together.
        power = power + depositAmount * (endBlock - block.number) when deposit
        power = power * amountAfterWithdraw / amountBeforeWithdraw when withdraw
        And when a new Lucky-Lucky pool period is started, all historical Board-staked Users get inited power:
               power = amount * (endBlock - startBlock);
        And when a Lucky-Lucky pool period finished, we compute totalPower = sum(user.power)
        and random a int between (0, totalPower) called sumluckyNumber,
        and At last pick up the lucky address just bigger than sumluckyNumber during the 
        process of sum(user.power)      
     */

    // start a new lucky lucky
    function startNewLucky(uint256 _endBlock) public onlyAdmin()
    {
        require(status == Status.Completed, "The last luckylucky has not finished");
        require(rewardPerPeriod > 0, "The reward cannot be 0");
        require(block.number < _endBlock, "end block invalid");
        status = Status.Open;
        startBlock = block.number;
        endBlock = _endBlock;
        initUserluckyNumber();
        emit LuckyOpen(rewardPerPeriod); 
    }

    // original get random , seems vrf not supporting heco-chain now :(
    function finishLuckyInternal() public onlyAdmin(){
        require(status == Status.Open, "status invalid");
        require(block.number > endBlock, "lucky not finished");
        address luckyAddress = getLuckyAddressInternal();
        status = Status.Completed;
        // lucky history info
        luckyIdCounter_ = luckyIdCounter_.add(1);
        uint256 luckyId = luckyIdCounter_;
        LuckyInfo memory luckyInfo = LuckyInfo(
            luckyId,
            rewardPerPeriod,
            luckyAddress,
            startBlock,
            endBlock
        );
        allLuckies_[luckyId] = luckyInfo;
        startBlock = 0;
        endBlock = 0;
        if(luckyAddress != address(0)){
            rewardToken.safeTransfer(luckyAddress, rewardPerPeriod);
        }
        emit LuckyCompleted(luckyId, rewardPerPeriod, luckyAddress);
    }

    // original get random and lucky address , seems vrf not supporting heco-chain now :(
    function getLuckyAddressInternal() internal view returns(address luckyAddress){
        uint256 totalPower = 0;
        for(uint256 i = 0; i < userAddresses.length; i ++ ){
            address address_ = userAddresses[i];
            totalPower = totalPower.add(userInfo[address_].power);
        }
        if(totalPower != 0){
            uint256 sumLuckyPower = uint256(keccak256(abi.encode(block.timestamp, block.difficulty))) % totalPower;
            uint256 luckyPower = 0;
            for(uint256 i = 0; i < userAddresses.length; i ++ ){
                address address_ = userAddresses[i];
                luckyPower = luckyPower.add(userInfo[address_].power);
                if(luckyPower >= sumLuckyPower){
                    luckyAddress = address_;
                    break;
                }
            }
        }else{
            luckyAddress = address(0);
        }
    }

    // end a lucky lucky , pick a lucky address to win @rewardPerPeriod rewardTokens
    function finishLucky(uint256 _seed) public onlyAdmin(){
        require(status == Status.Open, "status invalid");
        require(block.number > endBlock, "lucky not finished");
        uint256 totalPower = getTotalPower();
        requestId_ = randomGenerator_.getRandomNumber(totalPower, _seed);
        status = Status.Closed;
        emit RequestNumbers(totalPower, requestId_);
    }

    // random request returns, only randomGenerator is allowed to call
    function numbersDrawn(
        uint256 _totalPower,
        bytes32 _requestId, 
        uint256 _randomNumber
    ) override external onlyRandomGenerator(){
        require(status == Status.Closed, "status invalid, drawNumber first");
        if(requestId_ == _requestId) {
            // lucky history info
            address luckyAddress = getLuckyAddress(_totalPower, _randomNumber);
            status = Status.Completed;
            luckyIdCounter_ = luckyIdCounter_.add(1);
            uint256 luckyId = luckyIdCounter_;
            LuckyInfo memory luckyInfo = LuckyInfo(
                luckyId,
                rewardPerPeriod,
                luckyAddress,
                startBlock,
                endBlock
            );
            allLuckies_[luckyId] = luckyInfo;
            startBlock = 0;
            endBlock = 0;
            if(luckyAddress != address(0)){
                rewardToken.safeTransfer(luckyAddress, rewardPerPeriod);
            }
            emit LuckyCompleted(luckyId, rewardPerPeriod, luckyAddress);
        }
    }

    // get luckyAddress, within luckyNumber % totalPower to stop to get the lucky address
    function getLuckyAddress(uint256 totalPower, uint256 luckyNumber) internal view returns(address luckyAddress){
        if(totalPower == 0){
            luckyAddress = address(0);
        }else{
            uint256 sumluckyNumber = luckyNumber % totalPower;
            uint256 tmp = 0;
            for(uint256 i = 0; i < userAddresses.length; i ++ ){
                address address_ = userAddresses[i];
                tmp = tmp.add(userInfo[address_].power);
                if(tmp >= sumluckyNumber){
                    luckyAddress = address_;
                    break;
                }
            }
        }
    }

    // init stakers' power
    function initUserluckyNumber() internal{
        for(uint256 i = 0 ; i < userAddresses.length; i ++ ){
            address userAddress = userAddresses[i];
            UserInfo storage user = userInfo[userAddress];
            user.power = user.amount.mul(endBlock.sub(startBlock));
        }
    }

    // get total power
    function getTotalPower() internal view returns(uint256 totalPower){
        totalPower = 0;
        for(uint256 i = 0; i < userAddresses.length; i ++ ){
            address address_ = userAddresses[i];
            totalPower = totalPower.add(userInfo[address_].power);
        }
    }

    // Stake Board tokens to luckyluckyChef to win rewardPerPeriod tokens
    function deposit(uint256 _amount) public {
        require (_amount >= 0, 'amount less than 0');
        require (status == Status.Open, "luckylucky is not open");
        require (block.number >= startBlock, "luckylucky start block not reached");
        require (block.number < endBlock, "luckylucky end block reached");
        UserInfo storage user = userInfo[msg.sender];

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            user.power = user.power + _amount.mul(endBlock.sub(block.number));
            if(!user.init){
               userAddresses.push(msg.sender);
            }
            user.init = true;
        }

        if (_amount > 0) {
            board.safeTransferFrom(address(msg.sender), address(this), _amount);
        }
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw Cream tokens from STAKING.
    function withdraw(uint256 _amount) public {
        require (_amount >= 0, 'amount less than 0');
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not enough");

        if(_amount > 0) {
            uint256 formerAmount = user.amount;
            user.amount = user.amount.sub(_amount);
            user.power = user.power.div(formerAmount).mul(user.amount);
        }
        
        if(_amount > 0) {
            board.safeTransfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _amount);
    }

}
