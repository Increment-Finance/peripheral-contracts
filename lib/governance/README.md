# Overview

This repository contains the governance contracts that are to govern the Increment Protocol, the INCR Token, the vesting wallets for distributing tokens to initial investors, and the merkle distributor for airdrop distributions. These contracts are deployed on Ethereum mainnet in order to maintain the upmost security of the protocol.

The contracts are primarily prebuilt solutions provided by [Open Zeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) with a few small changes including token pausability and delegation of vested tokens. Additionally, the MerkleDistributor contract is an fork from [UMA](https://github.com/UMAprotocol/protocol/blob/master/packages/core/contracts/merkle-distributor/implementation/MerkleDistributor.sol) and has been [audited](https://docs.uma.xyz/resources/audit-and-bug-bounty-programs) by Open Zeppelin.

# Initial Parameters

Below are the initial parameters of the contracts at deployment.

### Token

The token is initially deployed in a paused state, with the only Owner being the Timelock. The Distributor role is held by the VestingWallets and MerkleDistributor so that they may transfer tokens to their receivers.

### Governor

The Governor starts with the following parameters and may be adjusted through governance:

| Parameter         | Value    |
| ----------------- | -------- |
| votingDelay       | 1 block  |
| votingPeriod      | 1 week   |
| proposalThreshold | 100 INCR |
| minQuorum         | 2%       |
| timelockDelay     | 2 days   |

# Addresses

The addresses of the deployed contracts on **Ethereum Mainnet**

| Contract           | Address                                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| INCR Token         | [0x1B9eBb707D87fbec93C49D9f2d994Ebb60461B9b](https://etherscan.io/address/0x1B9eBb707D87fbec93C49D9f2d994Ebb60461B9b) |
| Timelock           | [0xcce2065c1DC423451530BF7B493243234Ba1E849](https://etherscan.io/address/0xcce2065c1DC423451530BF7B493243234Ba1E849) |
| Governor           | [0x134E7ABaF7E8c440f634aE9f5532A4df53c19385](https://etherscan.io/address/0x134E7ABaF7E8c440f634aE9f5532A4df53c19385) |
| MerkleDistributor  | [0xce2C7ce74579D91972e393C11456555Ae461f667](https://etherscan.io/address/0xce2C7ce74579D91972e393C11456555Ae461f667) |
| VestingWallets[0]  | [0x7F2C5DF117Da4e87aaa785A58d0D58726a246801](https://etherscan.io/address/0x7F2C5DF117Da4e87aaa785A58d0D58726a246801) |
| VestingWallets[1]  | [0x08DF9c4438c5cEf8b443Cd4c4e2586a4E8063adE](https://etherscan.io/address/0x08DF9c4438c5cEf8b443Cd4c4e2586a4E8063adE) |
| VestingWallets[2]  | [0xdA5E5F97A150c04a719064875B33bbe23eDf6D28](https://etherscan.io/address/0xdA5E5F97A150c04a719064875B33bbe23eDf6D28) |
| VestingWallets[3]  | [0x79BA29c2dA113cdF07Cd08EE59eAc068C58AccF3](https://etherscan.io/address/0x79BA29c2dA113cdF07Cd08EE59eAc068C58AccF3) |
| VestingWallets[4]  | [0x93b8a2b6C703769d2d9ff0DF24C9b0D16a998126](https://etherscan.io/address/0x93b8a2b6C703769d2d9ff0DF24C9b0D16a998126) |
| VestingWallets[5]  | [0xCd0DD0A2ffD001B4907DB6c9846673894D008217](https://etherscan.io/address/0xCd0DD0A2ffD001B4907DB6c9846673894D008217) |
| VestingWallets[6]  | [0xDB14Fc98107F88F225FFbe783C2a0ceD0861740e](https://etherscan.io/address/0xDB14Fc98107F88F225FFbe783C2a0ceD0861740e) |
| VestingWallets[7]  | [0xc387F9923ce1DDf8Dc35E9224aD5C3EB6A4b22b3](https://etherscan.io/address/0xc387F9923ce1DDf8Dc35E9224aD5C3EB6A4b22b3) |
| VestingWallets[8]  | [0x072f77e0CD8e826A5991697443Dc048f3e944fc8](https://etherscan.io/address/0x072f77e0CD8e826A5991697443Dc048f3e944fc8) |
| VestingWallets[9]  | [0x2ce1a15CbAa7d314e3F8568952ee942E0106F34b](https://etherscan.io/address/0x2ce1a15CbAa7d314e3F8568952ee942E0106F34b) |
| VestingWallets[10] | [0x9C2Ab043F7943E54bfC756CEc11d91e5eb060199](https://etherscan.io/address/0x9C2Ab043F7943E54bfC756CEc11d91e5eb060199) |
| VestingWallets[11] | [0xC676Ed70Bdd9b7a83f13842253a3186E3606b8dd](https://etherscan.io/address/0xC676Ed70Bdd9b7a83f13842253a3186E3606b8dd) |
| VestingWallets[12] | [0x401e284cb0D670De6AB022aD487F16364f3737Fc](https://etherscan.io/address/0x401e284cb0D670De6AB022aD487F16364f3737Fc) |
| VestingWallets[13] | [0xaB990CDa07C8F99Fd805907c10db602D33d78E45](https://etherscan.io/address/0xaB990CDa07C8F99Fd805907c10db602D33d78E45) |
| VestingWallets[14] | [0x70b2925a62e251199a4d57472150414320bab9dc](https://etherscan.io/address/0x70b2925a62e251199a4d57472150414320bab9dc) |
