// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingRewardsTest is Test {
    StakingRewards internal staking;
    MockERC20 internal stakingToken;
    MockERC20 internal rewardsToken;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant DURATION = 7 days;
    uint256 internal constant REWARD = 70_000 ether; // 70k over 7 days -> ~0.1157/sec
    uint256 internal constant STAKE = 100 ether;

    function setUp() public {
        stakingToken = new MockERC20("Stake", "STK");
        rewardsToken = new MockERC20("Reward", "RWD");
        staking = new StakingRewards(owner, address(stakingToken), address(rewardsToken));

        // Fund stakers.
        stakingToken.mint(alice, STAKE);
        stakingToken.mint(bob, STAKE);

        vm.prank(alice);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(staking), type(uint256).max);
    }

    /* --------------------------------- Helpers ---------------------------------- */

    function _fundAndNotify(uint256 reward) internal {
        rewardsToken.mint(address(staking), reward);
        vm.prank(owner);
        staking.notifyRewardAmount(reward);
    }

    /* --------------------------------- Staking ---------------------------------- */

    function test_Stake_UpdatesBalances() public {
        vm.prank(alice);
        staking.stake(STAKE);

        assertEq(staking.balanceOf(alice), STAKE);
        assertEq(staking.totalSupply(), STAKE);
        assertEq(stakingToken.balanceOf(address(staking)), STAKE);
    }

    function test_Stake_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.ZeroAmount.selector);
        staking.stake(0);
    }

    function test_Withdraw_ReturnsTokens() public {
        vm.startPrank(alice);
        staking.stake(STAKE);
        staking.withdraw(STAKE);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakingToken.balanceOf(alice), STAKE);
    }

    function test_Withdraw_RevertsWhenExceedingBalance() public {
        vm.startPrank(alice);
        staking.stake(STAKE);
        vm.expectRevert(StakingRewards.InsufficientBalance.selector);
        staking.withdraw(STAKE + 1);
        vm.stopPrank();
    }

    /* --------------------------------- Rewards ---------------------------------- */

    function test_SingleStaker_EarnsFullRewardOverPeriod() public {
        vm.prank(alice);
        staking.stake(STAKE);
        _fundAndNotify(REWARD);

        vm.warp(block.timestamp + DURATION);

        // Allow for tiny rounding from integer division of rewardRate.
        uint256 earned = staking.earned(alice);
        assertApproxEqRel(earned, REWARD, 1e12); // within 0.0001%

        vm.prank(alice);
        staking.getReward();
        assertApproxEqRel(rewardsToken.balanceOf(alice), REWARD, 1e12);
    }

    function test_TwoStakers_SplitRewardsByShare() public {
        // Alice stakes 100, Bob stakes 100 -> 50/50 split.
        vm.prank(alice);
        staking.stake(STAKE);
        vm.prank(bob);
        staking.stake(STAKE);

        _fundAndNotify(REWARD);
        vm.warp(block.timestamp + DURATION);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        assertApproxEqRel(aliceEarned, REWARD / 2, 1e12);
        assertApproxEqRel(bobEarned, REWARD / 2, 1e12);
        assertApproxEqRel(aliceEarned, bobEarned, 1e12);
    }

    function test_Earned_IsZeroBeforeStaking() public {
        _fundAndNotify(REWARD);
        vm.warp(block.timestamp + DURATION);
        assertEq(staking.earned(alice), 0);
    }

    function test_RewardRate_SetByNotify() public {
        _fundAndNotify(REWARD);
        assertEq(staking.rewardRate(), REWARD / DURATION);
        assertEq(staking.getRewardForDuration(), (REWARD / DURATION) * DURATION);
    }

    function test_Exit_WithdrawsAndClaims() public {
        vm.prank(alice);
        staking.stake(STAKE);
        _fundAndNotify(REWARD);
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        staking.exit();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakingToken.balanceOf(alice), STAKE);
        assertApproxEqRel(rewardsToken.balanceOf(alice), REWARD, 1e12);
    }

    /* ----------------------------------- Admin ---------------------------------- */

    function test_NotifyRewardAmount_RevertsForNonOwner() public {
        rewardsToken.mint(address(staking), REWARD);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        staking.notifyRewardAmount(REWARD);
    }

    function test_NotifyRewardAmount_RevertsIfUnderfunded() public {
        // No tokens transferred to the contract -> rate exceeds balance.
        vm.prank(owner);
        vm.expectRevert(StakingRewards.RewardTooHigh.selector);
        staking.notifyRewardAmount(REWARD);
    }

    function test_SetRewardsDuration_RevertsWhilePeriodActive() public {
        _fundAndNotify(REWARD);
        vm.prank(owner);
        vm.expectRevert(StakingRewards.RewardPeriodActive.selector);
        staking.setRewardsDuration(14 days);
    }

    function test_SetRewardsDuration_SucceedsAfterPeriod() public {
        _fundAndNotify(REWARD);
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(owner);
        staking.setRewardsDuration(14 days);
        assertEq(staking.rewardsDuration(), 14 days);
    }

    /* ---------------------------------- Fuzzing --------------------------------- */

    function testFuzz_StakeWithdraw(uint256 amount) public {
        amount = bound(amount, 1, STAKE);
        vm.startPrank(alice);
        staking.stake(amount);
        assertEq(staking.balanceOf(alice), amount);
        staking.withdraw(amount);
        assertEq(staking.balanceOf(alice), 0);
        vm.stopPrank();
    }
}
