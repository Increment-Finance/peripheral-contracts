# IRewardController

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/IRewardController.sol)

**Author:**
webthethird

Interface for the RewardController contract

## Functions

### rewardTokensPerMarket

Gets the address of the reward token at the specified index in the array of reward tokens for a given market

```solidity
function rewardTokensPerMarket(address market, uint256 i) external view returns (address);
```

**Parameters**

| Name     | Type      | Description                   |
| -------- | --------- | ----------------------------- |
| `market` | `address` | The market address            |
| `i`      | `uint256` | The index of the reward token |

**Returns**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `<none>` | `address` | The address of the reward token |

### getNumMarkets

Gets the number of markets to be used for reward distribution

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getNumMarkets() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | Number of markets |

### getMaxMarketIdx

Gets the highest valid market index

```solidity
function getMaxMarketIdx() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                |
| -------- | --------- | -------------------------- |
| `<none>` | `uint256` | Highest valid market index |

### getMarketAddress

Gets the address of a market at a given index

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getMarketAddress(uint256 idx) external view returns (address);
```

**Parameters**

| Name  | Type      | Description         |
| ----- | --------- | ------------------- |
| `idx` | `uint256` | Index of the market |

**Returns**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `<none>` | `address` | Address of the market |

### getMarketIdx

Gets the index of an allowlisted market

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getMarketIdx(uint256 i) external view returns (uint256);
```

**Parameters**

| Name | Type      | Description                                                                                                                        |
| ---- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `i`  | `uint256` | Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule) |

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `uint256` | Index of the market in the market list |

### getMarketWeightIdx

Gets the index of the market in the rewardInfo.marketWeights array for a given reward token

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getMarketWeightIdx(address token, address market) external view returns (uint256);
```

**Parameters**

| Name     | Type      | Description                 |
| -------- | --------- | --------------------------- |
| `token`  | `address` | Address of the reward token |
| `market` | `address` | Address of the market       |

**Returns**

| Name     | Type      | Description                                                 |
| -------- | --------- | ----------------------------------------------------------- |
| `<none>` | `uint256` | Index of the market in the `rewardInfo.marketWeights` array |

### getCurrentPosition

Returns the current position of the user in the market (i.e., perpetual market or staked token)

```solidity
function getCurrentPosition(address user, address market) external view returns (uint256);
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `user`   | `address` | Address of the user   |
| `market` | `address` | Address of the market |

**Returns**

| Name     | Type      | Description                                |
| -------- | --------- | ------------------------------------------ |
| `<none>` | `uint256` | Current position of the user in the market |

### getRewardTokenCount

Gets the number of reward tokens for a given market

```solidity
function getRewardTokenCount(address market) external view returns (uint256);
```

**Parameters**

| Name     | Type      | Description        |
| -------- | --------- | ------------------ |
| `market` | `address` | The market address |

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `uint256` | Number of reward tokens for the market |

### getInitialTimestamp

Gets the timestamp when a reward token was registered

```solidity
function getInitialTimestamp(address rewardToken) external view returns (uint256);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type      | Description                                    |
| -------- | --------- | ---------------------------------------------- |
| `<none>` | `uint256` | Timestamp when the reward token was registered |

### getInitialInflationRate

Gets the inflation rate of a reward token (w/o factoring in reduction factor)

```solidity
function getInitialInflationRate(address rewardToken) external view returns (uint256);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type      | Description                                |
| -------- | --------- | ------------------------------------------ |
| `<none>` | `uint256` | Initial inflation rate of the reward token |

### getInflationRate

Gets the current inflation rate of a reward token (factoring in reduction factor)

_`inflationRate = initialInflationRate / reductionFactor^((block.timestamp - initialTimestamp) / secondsPerYear)`_

```solidity
function getInflationRate(address rewardToken) external view returns (uint256);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type      | Description                                |
| -------- | --------- | ------------------------------------------ |
| `<none>` | `uint256` | Current inflation rate of the reward token |

### getReductionFactor

Gets the reduction factor of a reward token

```solidity
function getReductionFactor(address rewardToken) external view returns (uint256);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type      | Description                          |
| -------- | --------- | ------------------------------------ |
| `<none>` | `uint256` | Reduction factor of the reward token |

### getRewardWeights

Gets the addresses and weights of all markets for a reward token

```solidity
function getRewardWeights(address rewardToken) external view returns (address[] memory, uint16[] memory);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type        | Description                                          |
| -------- | ----------- | ---------------------------------------------------- |
| `<none>` | `address[]` | List of market addresses receiving this reward token |
| `<none>` | `uint16[]`  | The corresponding weights for each market            |

### updateMarketRewards

Updates the reward accumulator for a given market

_Executes when any of the following variables are changed: `inflationRate`, `marketWeights`, `liquidity`_

```solidity
function updateMarketRewards(address market) external;
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `market` | `address` | Address of the market |

### updateRewardWeights

Sets the market addresses and reward weights for a reward token

```solidity
function updateRewardWeights(address rewardToken, address[] calldata markets, uint16[] calldata weights) external;
```

**Parameters**

| Name          | Type        | Description                                 |
| ------------- | ----------- | ------------------------------------------- |
| `rewardToken` | `address`   | Address of the reward token                 |
| `markets`     | `address[]` | List of market addresses to receive rewards |
| `weights`     | `uint16[]`  | List of weights for each market             |

### updateInitialInflationRate

Sets the initial inflation rate used to calculate emissions over time for a given reward token

_Current inflation rate still factors in the reduction factor and time elapsed since the initial timestamp_

```solidity
function updateInitialInflationRate(address rewardToken, uint256 newInitialInflationRate) external;
```

**Parameters**

| Name                      | Type      | Description                                           |
| ------------------------- | --------- | ----------------------------------------------------- |
| `rewardToken`             | `address` | Address of the reward token                           |
| `newInitialInflationRate` | `uint256` | The new inflation rate in tokens/year, scaled by 1e18 |

### updateReductionFactor

Sets the reduction factor used to reduce emissions over time for a given reward token

```solidity
function updateReductionFactor(address rewardToken, uint256 newReductionFactor) external;
```

**Parameters**

| Name                 | Type      | Description                              |
| -------------------- | --------- | ---------------------------------------- |
| `rewardToken`        | `address` | Address of the reward token              |
| `newReductionFactor` | `uint256` | The new reduction factor, scaled by 1e18 |

### setPaused

Pauses/unpauses the reward accrual for a reward token

_Does not pause gradual reduction of inflation rate over time due to reduction factor_

```solidity
function setPaused(address rewardToken, bool paused) external;
```

**Parameters**

| Name          | Type      | Description                                  |
| ------------- | --------- | -------------------------------------------- |
| `rewardToken` | `address` | Address of the reward token                  |
| `paused`      | `bool`    | Whether to pause or unpause the reward token |

## Events

### RewardTokenAdded

Emitted when a new reward token is added

```solidity
event RewardTokenAdded(
    address indexed rewardToken, uint256 initialTimestamp, uint256 initialInflationRate, uint256 initialReductionFactor
);
```

**Parameters**

| Name                     | Type      | Description                                   |
| ------------------------ | --------- | --------------------------------------------- |
| `rewardToken`            | `address` | Reward token address                          |
| `initialTimestamp`       | `uint256` | Timestamp when reward token was added         |
| `initialInflationRate`   | `uint256` | Initial inflation rate for the reward token   |
| `initialReductionFactor` | `uint256` | Initial reduction factor for the reward token |

### RewardTokenRemoved

Emitted when governance removes a reward token

```solidity
event RewardTokenRemoved(address indexed rewardToken, uint256 unclaimedRewards, uint256 remainingBalance);
```

**Parameters**

| Name               | Type      | Description                                                   |
| ------------------ | --------- | ------------------------------------------------------------- |
| `rewardToken`      | `address` | The reward token address                                      |
| `unclaimedRewards` | `uint256` | The amount of reward tokens still claimable                   |
| `remainingBalance` | `uint256` | The remaining balance of the reward token, sent to governance |

### MarketRemovedFromRewards

Emitted when a reward token is removed from a market's list of rewards

```solidity
event MarketRemovedFromRewards(address indexed market, address indexed rewardToken);
```

**Parameters**

| Name          | Type      | Description              |
| ------------- | --------- | ------------------------ |
| `market`      | `address` | The market address       |
| `rewardToken` | `address` | The reward token address |

### RewardTokenShortfall

Emitted when the contract runs out of a reward token

```solidity
event RewardTokenShortfall(address indexed rewardToken, uint256 shortfallAmount);
```

**Parameters**

| Name              | Type      | Description                                               |
| ----------------- | --------- | --------------------------------------------------------- |
| `rewardToken`     | `address` | The reward token address                                  |
| `shortfallAmount` | `uint256` | The amount of reward tokens needed to fulfill all rewards |

### NewWeight

Emitted when a gauge weight is updated

```solidity
event NewWeight(address indexed market, address indexed rewardToken, uint16 newWeight);
```

**Parameters**

| Name          | Type      | Description                                    |
| ------------- | --------- | ---------------------------------------------- |
| `market`      | `address` | The address of the perp market or staked token |
| `rewardToken` | `address` | The reward token address                       |
| `newWeight`   | `uint16`  | The new weight value                           |

### NewInitialInflationRate

Emitted when a new inflation rate is set by governance

```solidity
event NewInitialInflationRate(address indexed rewardToken, uint256 newRate);
```

**Parameters**

| Name          | Type      | Description            |
| ------------- | --------- | ---------------------- |
| `rewardToken` | `address` |                        |
| `newRate`     | `uint256` | The new inflation rate |

### NewReductionFactor

Emitted when a new reduction factor is set by governance

```solidity
event NewReductionFactor(address indexed rewardToken, uint256 newFactor);
```

**Parameters**

| Name          | Type      | Description              |
| ------------- | --------- | ------------------------ |
| `rewardToken` | `address` |                          |
| `newFactor`   | `uint256` | The new reduction factor |

## Errors

### RewardController_AboveMaxRewardTokens

Error returned when trying to add a reward token if the max number of reward tokens has been reached

```solidity
error RewardController_AboveMaxRewardTokens(uint256 max, address market);
```

**Parameters**

| Name     | Type      | Description                                                              |
| -------- | --------- | ------------------------------------------------------------------------ |
| `max`    | `uint256` | The maximum number of reward tokens allowed                              |
| `market` | `address` | The market address which has reached the maximum number of reward tokens |

### RewardController_AboveMaxInflationRate

Error returned when trying to set the inflation rate to a value that is too high

```solidity
error RewardController_AboveMaxInflationRate(uint256 rate, uint256 max);
```

**Parameters**

| Name   | Type      | Description               |
| ------ | --------- | ------------------------- |
| `rate` | `uint256` | The value that was passed |
| `max`  | `uint256` | The maximum allowed value |

### RewardController_BelowMinReductionFactor

Error returned when trying to set the reduction factor to a value that is too low

```solidity
error RewardController_BelowMinReductionFactor(uint256 factor, uint256 min);
```

**Parameters**

| Name     | Type      | Description               |
| -------- | --------- | ------------------------- |
| `factor` | `uint256` | The value that was passed |
| `min`    | `uint256` | The minimum allowed value |

### RewardController_InvalidRewardTokenAddress

Error returned when passing an invalid reward token address to a function

```solidity
error RewardController_InvalidRewardTokenAddress(address invalidAddress);
```

**Parameters**

| Name             | Type      | Description                 |
| ---------------- | --------- | --------------------------- |
| `invalidAddress` | `address` | The address that was passed |

### RewardController_MarketHasNoRewardWeight

Error returned when a given market address has no reward weight stored in the RewardInfo for a given reward token

```solidity
error RewardController_MarketHasNoRewardWeight(address market, address rewardToken);
```

**Parameters**

| Name          | Type      | Description              |
| ------------- | --------- | ------------------------ |
| `market`      | `address` | The market address       |
| `rewardToken` | `address` | The reward token address |

### RewardController_IncorrectWeightsCount

Error returned when trying to set the reward weights with markets and weights arrays of different lengths

```solidity
error RewardController_IncorrectWeightsCount(uint256 actual, uint256 expected);
```

**Parameters**

| Name       | Type      | Description                              |
| ---------- | --------- | ---------------------------------------- |
| `actual`   | `uint256` | The length of the weights array provided |
| `expected` | `uint256` | The length of the markets array provided |

### RewardController_IncorrectWeightsSum

Error returned when the sum of the weights provided is not equal to 100% (in basis points)

```solidity
error RewardController_IncorrectWeightsSum(uint16 actual, uint16 expected);
```

**Parameters**

| Name       | Type     | Description                                   |
| ---------- | -------- | --------------------------------------------- |
| `actual`   | `uint16` | The sum of the weights provided               |
| `expected` | `uint16` | The expected sum of the weights (i.e., 10000) |

### RewardController_WeightExceedsMax

Error returned when one of the weights provided is greater than the maximum allowed weight (i.e., 100% in basis points)

```solidity
error RewardController_WeightExceedsMax(uint16 weight, uint16 max);
```

**Parameters**

| Name     | Type     | Description                              |
| -------- | -------- | ---------------------------------------- |
| `weight` | `uint16` | The weight that was passed               |
| `max`    | `uint16` | The maximum allowed weight (i.e., 10000) |