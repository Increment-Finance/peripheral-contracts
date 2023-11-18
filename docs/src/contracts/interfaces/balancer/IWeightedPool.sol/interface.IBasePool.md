# IBasePool
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IWeightedPool.sol)

**Inherits:**
[IPoolSwapStructs](/contracts/interfaces/balancer/IWeightedPool.sol/interface.IPoolSwapStructs.md), [IControlledPool](/contracts/interfaces/balancer/IWeightedPool.sol/interface.IControlledPool.md), [IBalancerPoolToken](/contracts/interfaces/balancer/IWeightedPool.sol/interface.IBalancerPoolToken.md), [ITemporarilyPausable](/contracts/interfaces/balancer/IVault.sol/interface.ITemporarilyPausable.md), [IRecoveryMode](/contracts/interfaces/balancer/IWeightedPool.sol/interface.IRecoveryMode.md)


## Functions
### onJoinPool

*Called by the Vault when a user calls `IVault.joinPool` to add liquidity to this Pool. Returns how many of
each registered token the user should provide, as well as the amount of protocol fees the Pool owes to the Vault.
The Vault will then take tokens from `sender` and add them to the Pool's balances, as well as collect
the reported amount in protocol fees, which the pool should calculate based on `protocolSwapFeePercentage`.
Protocol fees are reported and charged on join events so that the Pool is free of debt whenever new users join.
`sender` is the account performing the join (from which tokens will be withdrawn), and `recipient` is the account
designated to receive any benefits (typically pool shares). `balances` contains the total balances
for each token the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
`lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
balance.
`userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
join (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
Contracts implementing this function should check that the caller is indeed the Vault before performing any
state-changing operations, such as minting pool shares.*


```solidity
function onJoinPool(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
) external returns (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts);
```

### onExitPool

*Called by the Vault when a user calls `IVault.exitPool` to remove liquidity from this Pool. Returns how many
tokens the Vault should deduct from the Pool's balances, as well as the amount of protocol fees the Pool owes
to the Vault. The Vault will then take tokens from the Pool's balances and send them to `recipient`,
as well as collect the reported amount in protocol fees, which the Pool should calculate based on
`protocolSwapFeePercentage`.
Protocol fees are charged on exit events to guarantee that users exiting the Pool have paid their share.
`sender` is the account performing the exit (typically the pool shareholder), and `recipient` is the account
to which the Vault will send the proceeds. `balances` contains the total token balances for each token
the Pool registered in the Vault, in the same order that `IVault.getPoolTokens` would return.
`lastChangeBlock` is the last block in which *any* of the Pool's registered tokens last changed its total
balance.
`userData` contains any pool-specific instructions needed to perform the calculations, such as the type of
exit (e.g., proportional given an amount of pool shares, single-asset, multi-asset, etc.)
Contracts implementing this function should check that the caller is indeed the Vault before performing any
state-changing operations, such as burning pool shares.*


```solidity
function onExitPool(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
) external returns (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts);
```

### getPoolId

*Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).*


```solidity
function getPoolId() external view returns (bytes32);
```

### getSwapFeePercentage

*Returns the current swap fee percentage as a 18 decimal fixed point number, so e.g. 1e17 corresponds to a
10% swap fee.*


```solidity
function getSwapFeePercentage() external view returns (uint256);
```

### getScalingFactors

*Returns the scaling factors of each of the Pool's tokens. This is an implementation detail that is typically
not relevant for outside parties, but which might be useful for some types of Pools.*


```solidity
function getScalingFactors() external view returns (uint256[] memory);
```

### queryJoin


```solidity
function queryJoin(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
) external returns (uint256 bptOut, uint256[] memory amountsIn);
```

### queryExit


```solidity
function queryExit(
    bytes32 poolId,
    address sender,
    address recipient,
    uint256[] memory balances,
    uint256 lastChangeBlock,
    uint256 protocolSwapFeePercentage,
    bytes memory userData
) external returns (uint256 bptIn, uint256[] memory amountsOut);
```
