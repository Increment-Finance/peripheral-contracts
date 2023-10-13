# Increment Finance: Peripheral Contracts

This repository contains peripheral smart contracts for [Increment Protocol](https://github.com/Increment-Finance/increment-protocol). Specifically, it contains contracts for distributing reward tokens to liquidity providers in the Perpetual markets, as well as a Safety Module which rewards stakers for providing economic security to the protocol.

## Setup

To get started with this project, follow these steps:

1. Clone the repository to your local machine:
   ```
   git clone https://github.com/Increment-Finance/peripheral-contracts.git && cd peripheral-contracts
   ```
2. Initialize the submodules by running the following command:
   ```
   git submodule update --init
   ```
3. Create a .env file with an RPC node provider URL (see example.env):
   ```
   ETH_NODE_URI_MAINNET="https://mainnet.infura.io/v3/<YOUR_INFURA_KEY>"
   ```

## Testing

To run the Foundry tests for this project, you will need a .env file with an RPC node provider API key as shown above. You will also need to have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed. Once you are ready, run the following command from the repo's root directory:

```
source .env && forge test --fork-url $ETH_NODE_URI_MAINNET
```
