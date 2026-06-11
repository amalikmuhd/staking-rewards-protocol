// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Drives bounded, randomized sequences of protocol actions against
///         StakingRewards for invariant testing. A fixed set of actors stake,
///         withdraw, and claim; the owner periodically funds new reward periods
///         and time advances between actions.
contract Handler is Test {
    StakingRewards public immutable staking;
    MockERC20 public immutable stakingToken;
    MockERC20 public immutable rewardsToken;
    address public immutable owner;

    address[] public actors;
    address internal currentActor;

    uint256 public constant MAX_STAKE = 1_000_000 ether;
    uint256 public constant MAX_REWARD = 1_000_000 ether;

    // Ghost totals for cross-checking against contract state.
    uint256 public ghost_totalRewardsFunded;
    uint256 public ghost_totalRewardsClaimed;

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(StakingRewards _staking, MockERC20 _stakingToken, MockERC20 _rewardsToken, address _owner) {
        staking = _staking;
        stakingToken = _stakingToken;
        rewardsToken = _rewardsToken;
        owner = _owner;

        for (uint256 i = 0; i < 4; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", vm.toString(i)))));
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function stake(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        amount = bound(amount, 1, MAX_STAKE);
        stakingToken.mint(currentActor, amount);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);
    }

    function withdraw(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        uint256 bal = staking.balanceOf(currentActor);
        if (bal == 0) return;
        staking.withdraw(bound(amount, 1, bal));
    }

    function getReward(uint256 actorSeed) external useActor(actorSeed) {
        uint256 before = rewardsToken.balanceOf(currentActor);
        staking.getReward();
        ghost_totalRewardsClaimed += rewardsToken.balanceOf(currentActor) - before;
    }

    function notifyReward(uint256 amount) external {
        amount = bound(amount, 1e15, MAX_REWARD);
        rewardsToken.mint(address(staking), amount);
        ghost_totalRewardsFunded += amount;
        vm.prank(owner);
        staking.notifyRewardAmount(amount);
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 10 days));
    }
}
