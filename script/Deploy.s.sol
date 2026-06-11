// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

/// @notice Deploys StakingRewards using addresses from the environment.
/// @dev Required env vars:
///        OWNER          - address that can notify rewards / set duration
///        STAKING_TOKEN  - ERC20 users stake
///        REWARDS_TOKEN  - ERC20 paid out as rewards
///      Example:
///        forge script script/Deploy.s.sol:DeployStakingRewards \
///          --rpc-url $RPC_URL --broadcast --verify
contract DeployStakingRewards is Script {
    function run() external returns (StakingRewards staking) {
        address owner = vm.envAddress("OWNER");
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardsToken = vm.envAddress("REWARDS_TOKEN");

        vm.startBroadcast();
        staking = new StakingRewards(owner, stakingToken, rewardsToken);
        vm.stopBroadcast();

        console.log("StakingRewards deployed at:", address(staking));
        console.log("  owner:        ", owner);
        console.log("  stakingToken: ", stakingToken);
        console.log("  rewardsToken: ", rewardsToken);
    }
}
