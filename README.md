[![Fuzzing](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/unit.yml/badge.svg)](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/unit.yml) [![Line Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/increment-bot/6d6d5f849f8fb108519cfe2bbf5c21f6/raw/peripheral-contracts-line-coverage__heads_main.json)](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/coverage.yml) [![Statement Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/increment-bot/6d6d5f849f8fb108519cfe2bbf5c21f6/raw/peripheral-contracts-statement-coverage__heads_main.json)](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/coverage.yml) [![Branch Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/increment-bot/6d6d5f849f8fb108519cfe2bbf5c21f6/raw/peripheral-contracts-branch-coverage__heads_main.json)](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/coverage.yml) [![Function Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/increment-bot/6d6d5f849f8fb108519cfe2bbf5c21f6/raw/peripheral-contracts-function-coverage__heads_main.json)](https://github.com/Increment-Finance/peripheral-contracts/actions/workflows/coverage.yml)

# Increment Finance: Peripheral Contracts

This repository contains peripheral smart contracts for [Increment Protocol](https://github.com/Increment-Finance/increment-protocol). Specifically, it contains contracts for distributing reward tokens to liquidity providers in the Perpetual markets, as well as a Safety Module which rewards stakers for providing economic security to the protocol. The Safety Module is comprised of a central SafetyModule contract, a StakedToken contract for staking, an SMRewardDistributor for handling reward distribution to stakers, and an AuctionModule contract for auctioning slashed tokens in the event of a shortfall in the protocol.

## Setup

To get started with this project, follow these steps:

1. Clone the repository to your local machine:
   ```
   git clone https://github.com/Increment-Finance/peripheral-contracts.git && cd peripheral-contracts
   ```
2. Initialize the submodules and recursively install their submodules by running the following command:
   ```
   git submodule update --init && forge install
   ```

## Testing

To run the Foundry tests for this project, you will need to have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed. You will also need an RPC node provider API key and corresponding URL, which should be stored in a .env file as `MAINNET_RPC_URL=<your API URL here>`. See [example.env](example.env) for an example.

To run just the unit tests, run the following command from the repo's root directory:

```
source .env && forge test --match-path "test/unit/**"
```

To run the invariant fuzzing tests, which take longer, run the following command from the repo's root directory:

```
source .env && forge test --match-path "test/invariant/**"
```

Or just run one of the invariant fuzzing tests, i.e., the SafetyModule tests:

```
source .env && forge test --match-path test/invariant/SafetyModuleInvariantTest.sol
```
