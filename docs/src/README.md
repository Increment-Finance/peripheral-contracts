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

## Testing

To run the Foundry tests for this project, you will need an RPC node provider API key and corresponding URL, as shown below. You will also need to have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed. Once you are ready, run the following command from the repo's root directory:

```
source .env && forge test --fork-url https://mainnet.infura.io/v3/<YOUR_INFURA_KEY>
```

_Note: if you use some RPC provider other than Infura, just replace the entire URL rather than just the key_
