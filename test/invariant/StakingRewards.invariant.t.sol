// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Handler} from "./Handler.sol";

contract StakingRewardsInvariantTest is Test {
    StakingRewards internal staking;
    MockERC20 internal stakingToken;
    MockERC20 internal rewardsToken;
    Handler internal handler;

    address internal owner = makeAddr("owner");

    function setUp() public {
        stakingToken = new MockERC20("Stake", "STK");
        rewardsToken = new MockERC20("Reward", "RWD");
        staking = new StakingRewards(owner, address(stakingToken), address(rewardsToken));

        handler = new Handler(staking, stakingToken, rewardsToken, owner);
        targetContract(address(handler));
    }

    /// @dev The contract must always hold at least the total staked principal;
    ///      staking tokens only enter via stake() and leave via withdraw().
    function invariant_stakingTokenFullyBacked() public view {
        assertGe(stakingToken.balanceOf(address(staking)), staking.totalSupply());
    }

    /// @dev totalSupply must equal the sum of individual staked balances.
    function invariant_totalSupplyEqualsSumOfBalances() public view {
        uint256 sum;
        uint256 n = handler.actorsLength();
        for (uint256 i; i < n; i++) {
            sum += staking.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, staking.totalSupply());
    }

    /// @dev The core solvency property: the contract can always pay every staker
    ///      what they have currently earned. notifyRewardAmount caps the rate
    ///      against the funded balance, so emissions never exceed what was funded.
    function invariant_rewardsSolvent() public view {
        uint256 owed;
        uint256 n = handler.actorsLength();
        for (uint256 i; i < n; i++) {
            owed += staking.earned(handler.actorAt(i));
        }
        assertGe(rewardsToken.balanceOf(address(staking)), owed);
    }

    /// @dev Rewards paid out can never exceed rewards funded by the owner.
    function invariant_claimsNeverExceedFunding() public view {
        assertLe(handler.ghost_totalRewardsClaimed(), handler.ghost_totalRewardsFunded());
    }
}
