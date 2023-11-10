# IPerpRewardDistributor
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/IPerpRewardDistributor.sol)


## Functions
### clearingHouse

Gets the address of the ClearingHouse contract which stores the list of Perpetuals and can call updateStakingPosition


```solidity
function clearingHouse() external view returns (IClearingHouse);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IClearingHouse`|Address of the ClearingHouse contract|


### earlyWithdrawalThreshold

Gets the number of seconds that a user must leave their liquidity in the market to avoid the early withdrawal penalty


```solidity
function earlyWithdrawalThreshold() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Length of the early withdrawal period in seconds|


## Errors
### PerpRewardDistributor_CallerIsNotClearingHouse
Error returned when the caller of updateStakingPosition is not the ClearingHouse


```solidity
error PerpRewardDistributor_CallerIsNotClearingHouse(address caller);
```

