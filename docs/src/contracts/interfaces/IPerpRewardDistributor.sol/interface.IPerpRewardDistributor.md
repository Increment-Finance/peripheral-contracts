# IPerpRewardDistributor
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/IPerpRewardDistributor.sol)


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

