# Staking & Rewards Protocol

A simple staking protocol built with [Foundry](https://book.getfoundry.sh/).

Users stake **STK** tokens to earn rewards distributed linearly over a reward
period (Synthetix-style accounting). Anyone who has staked continuously for at
least **7 days** can also claim a **RewardNFT** — an ERC721 badge that can only
be minted by the staking contract, once per address.

## Contracts

| Contract | Description |
|----------|-------------|
| `StakingRewards` | Stake `stakingToken`, earn `rewardsToken`, claim a RewardNFT after 7 days. |
| `RewardNFT` | ERC721 reward badge; mintable only by the `StakingRewards` contract. |

## Install & Build

```shell
forge install
forge build
```

## Test

```shell
forge test
```

## Deploy

The deploy script (`script/Deploy.s.sol`) reads three environment variables:

| Variable | Description |
|----------|-------------|
| `OWNER` | Address that can fund rewards and configure the contract. |
| `STAKING_TOKEN` | ERC20 that users stake. |
| `REWARDS_TOKEN` | ERC20 paid out as rewards. |

```shell
export OWNER=0x...
export STAKING_TOKEN=0x...
export REWARDS_TOKEN=0x...

forge script script/Deploy.s.sol:DeployStakingRewards \
  --rpc-url $RPC_URL --broadcast
```

### Deploy order

Because each contract needs the other's address, deploy in this order:

1. Deploy **`StakingRewards`**.
2. Deploy **`RewardNFT`**, passing the `StakingRewards` address as the `minter`.
3. Call **`StakingRewards.setRewardNFT(rewardNFTAddress)`** to wire the NFT in.
