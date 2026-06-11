// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakingRewards
/// @notice Stake `stakingToken` to earn `rewardsToken`, distributed linearly over a
///         fixed reward period. Rewards accrue per staked token, pro-rata over time.
/// @dev Adapted from the Synthetix StakingRewards design for OpenZeppelin v5.
contract StakingRewards is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /* ----------------------------------- State ---------------------------------- */

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    /// @notice Reward tokens emitted per second during an active period.
    uint256 public rewardRate;
    /// @notice Length of a reward period; set via `setRewardsDuration`.
    uint256 public rewardsDuration = 7 days;
    /// @notice Timestamp at which the current reward period ends.
    uint256 public periodFinish;
    /// @notice Last time reward accounting was updated.
    uint256 public lastUpdateTime;
    /// @notice Accumulated reward per staked token, scaled by 1e18.
    uint256 public rewardPerTokenStored;

    /// @notice Reward-per-token already accounted to each user.
    mapping(address account => uint256) public userRewardPerTokenPaid;
    /// @notice Rewards earned but not yet claimed by each user.
    mapping(address account => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address account => uint256) private _balances;

    /* ----------------------------------- Events --------------------------------- */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);

    /* ----------------------------------- Errors --------------------------------- */

    error ZeroAmount();
    error InsufficientBalance();
    error RewardTooHigh();
    error RewardPeriodActive();

    /* --------------------------------- Constructor ------------------------------ */

    constructor(address _owner, address _stakingToken, address _rewardsToken) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    /* ----------------------------------- Modifiers ------------------------------ */

    /// @dev Settles global and per-account reward accounting before a state change.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ------------------------------------ Views --------------------------------- */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice The last timestamp at which rewards are still accruing.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Current accumulated reward per staked token, scaled by 1e18.
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply;
    }

    /// @notice Rewards an account has earned but not yet claimed.
    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /// @notice Total rewards distributed over the full current period.
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* --------------------------------- User actions ----------------------------- */

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Withdraw the full stake and claim outstanding rewards in one call.
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* --------------------------------- Admin actions ---------------------------- */

    /// @notice Fund a new reward period. The owner must transfer `reward` tokens to
    ///         this contract before (or as part of) calling, then this starts/extends
    ///         distribution over `rewardsDuration`.
    /// @dev Caps the rate against the contract's reward balance to prevent over-promising.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward is actually covered by the contract's balance.
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (rewardRate > balance / rewardsDuration) revert RewardTooHigh();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /// @notice Update the reward period length. Only allowed once the current period ends.
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp <= periodFinish) revert RewardPeriodActive();
        if (_rewardsDuration == 0) revert ZeroAmount();
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }
}
