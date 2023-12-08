# RewardController

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/ecb136b3c508e89c22b16cec8dcfd7e319381983/contracts/RewardController.sol)

**Inherits:**
[IRewardController](/contracts/interfaces/IRewardController.sol/interface.IRewardController.md), IncreAccessControl, Pausable, ReentrancyGuard

**Author:**
webthethird

Base contract for storing and updating reward info for multiple reward tokens, each with

- a gradually decreasing emission rate, based on an initial inflation rate, reduction factor, and time elapsed
- a list of markets for which the reward token is distributed
- a list of weights representing the percentage of rewards that go to each market

## State Variables

### MAX_INFLATION_RATE

Maximum inflation rate, applies to all reward tokens

```solidity
uint256 public constant MAX_INFLATION_RATE = 5e24;
```

### MIN_REDUCTION_FACTOR

Minimum reduction factor, applies to all reward tokens

```solidity
uint256 public constant MIN_REDUCTION_FACTOR = 1e18;
```

### MAX_REWARD_TOKENS

Maximum number of reward tokens allowed

```solidity
uint256 public constant MAX_REWARD_TOKENS = 10;
```

### rewardTokens

List of reward token addresses

_Length must be <= `MAX_REWARD_TOKENS`_

```solidity
address[] public rewardTokens;
```

### rewardInfoByToken

Info for each registered reward token

```solidity
mapping(address => RewardInfo) internal rewardInfoByToken;
```

## Functions

### getRewardTokenCount

Gets the number of reward tokens

```solidity
function getRewardTokenCount() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `<none>` | `uint256` | Number of reward tokens |

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

| Name     | Type        | Description                                              |
| -------- | ----------- | -------------------------------------------------------- |
| `<none>` | `address[]` | List of market addresses and their corresponding weights |
| `<none>` | `uint16[]`  | The corresponding weights for each market                |

### getMarketWeightIdx

Gets the index of the market in the rewardInfo.marketWeights array for a given reward token

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getMarketWeightIdx(address token, address market) public view virtual returns (int256);
```

**Parameters**

| Name     | Type      | Description                 |
| -------- | --------- | --------------------------- |
| `token`  | `address` | Address of the reward token |
| `market` | `address` | Address of the market       |

**Returns**

| Name     | Type     | Description                                                                                   |
| -------- | -------- | --------------------------------------------------------------------------------------------- |
| `<none>` | `int256` | Index of the market in the `rewardInfo.marketWeights` array, or -1 if the market is not found |

### isTokenPaused

Gets whether a reward token is paused

```solidity
function isTokenPaused(address rewardToken) external view returns (bool);
```

**Parameters**

| Name          | Type      | Description                 |
| ------------- | --------- | --------------------------- |
| `rewardToken` | `address` | Address of the reward token |

**Returns**

| Name     | Type   | Description                                         |
| -------- | ------ | --------------------------------------------------- |
| `<none>` | `bool` | True if the reward token is paused, false otherwise |

### updateRewardWeights

Sets the market addresses and reward weights for a reward token

_Only callable by Governance_

```solidity
function updateRewardWeights(address rewardToken, address[] calldata markets, uint16[] calldata weights)
    external
    nonReentrant
    onlyRole(GOVERNANCE);
```

**Parameters**

| Name          | Type        | Description                                 |
| ------------- | ----------- | ------------------------------------------- |
| `rewardToken` | `address`   | Address of the reward token                 |
| `markets`     | `address[]` | List of market addresses to receive rewards |
| `weights`     | `uint16[]`  | List of weights for each market             |

### updateInitialInflationRate

Sets the initial inflation rate used to calculate emissions over time for a given reward token

_Only callable by Governance_

```solidity
function updateInitialInflationRate(address rewardToken, uint256 newInitialInflationRate)
    external
    onlyRole(GOVERNANCE);
```

**Parameters**

| Name                      | Type      | Description                                           |
| ------------------------- | --------- | ----------------------------------------------------- |
| `rewardToken`             | `address` | Address of the reward token                           |
| `newInitialInflationRate` | `uint256` | The new inflation rate in tokens/year, scaled by 1e18 |

### updateReductionFactor

Sets the reduction factor used to reduce emissions over time for a given reward token

_Only callable by Governance_

```solidity
function updateReductionFactor(address rewardToken, uint256 newReductionFactor) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                 | Type      | Description                              |
| -------------------- | --------- | ---------------------------------------- |
| `rewardToken`        | `address` | Address of the reward token              |
| `newReductionFactor` | `uint256` | The new reduction factor, scaled by 1e18 |

### pause

Pause the contract

_Can only be called by Emergency Admin_

```solidity
function pause() external override onlyRole(EMERGENCY_ADMIN);
```

### unpause

Unpause the contract

_Can only be called by Emergency Admin_

```solidity
function unpause() external override onlyRole(EMERGENCY_ADMIN);
```

### setPaused

Pauses/unpauses the reward accrual for a particular reward token

_Only callable by Emergency Admin_

```solidity
function setPaused(address rewardToken, bool paused) external onlyRole(EMERGENCY_ADMIN);
```

**Parameters**

| Name          | Type      | Description                                  |
| ------------- | --------- | -------------------------------------------- |
| `rewardToken` | `address` | Address of the reward token                  |
| `paused`      | `bool`    | Whether to pause or unpause the reward token |

### \_updateMarketRewards

Updates the reward accumulator for a given market

_Executes when any of the following variables are changed: `inflationRate`, `marketWeights`, `liquidity`_

```solidity
function _updateMarketRewards(address market) internal virtual;
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `market` | `address` | Address of the market |

### \_getNumMarkets

Gets the number of markets to be used for reward distribution

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getNumMarkets() internal view virtual returns (uint256);
```

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | Number of markets |

### \_getCurrentPosition

Returns the current position of the user in the market (i.e., perpetual market or staked token)

```solidity
function _getCurrentPosition(address user, address market) internal view virtual returns (uint256);
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

### \_getMarketAddress

Gets the address of a market at a given index

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getMarketAddress(uint256 idx) internal view virtual returns (address);
```

**Parameters**

| Name  | Type      | Description         |
| ----- | --------- | ------------------- |
| `idx` | `uint256` | Index of the market |

**Returns**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `<none>` | `address` | Address of the market |

### \_getMarketIdx

Gets the index of an allowlisted market

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getMarketIdx(uint256 i) internal view virtual returns (uint256);
```

**Parameters**

| Name | Type      | Description                                                                                                                        |
| ---- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `i`  | `uint256` | Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule) |

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `uint256` | Index of the market in the market list |

## Structs

### RewardInfo

Data structure containing essential info for each reward token

```solidity
struct RewardInfo {
    IERC20Metadata token;
    bool paused;
    uint256 initialTimestamp;
    uint256 initialInflationRate;
    uint256 reductionFactor;
    address[] marketAddresses;
    uint16[] marketWeights;
}
```

**Properties**

| Name                   | Type             | Description                                                         |
| ---------------------- | ---------------- | ------------------------------------------------------------------- |
| `token`                | `IERC20Metadata` | Address of the reward token                                         |
| `paused`               | `bool`           | Whether the reward token accrual is paused                          |
| `initialTimestamp`     | `uint256`        | Time when the reward token was added                                |
| `initialInflationRate` | `uint256`        | Initial rate of reward token emission per year                      |
| `reductionFactor`      | `uint256`        | Factor by which the inflation rate is reduced each year             |
| `marketAddresses`      | `address[]`      | List of markets for which the reward token is distributed           |
| `marketWeights`        | `uint16[]`       | Market reward weights as basis points, i.e., 100 = 1%, 10000 = 100% |
