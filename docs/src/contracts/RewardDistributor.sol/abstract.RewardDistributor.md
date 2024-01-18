# RewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/RewardDistributor.sol)

**Inherits:**
[IRewardDistributor](/contracts/interfaces/IRewardDistributor.sol/interface.IRewardDistributor.md), IRewardContract, [RewardController](/contracts/RewardController.sol/abstract.RewardController.md)

**Author:**
webthethird

Abstract contract responsible for accruing and distributing rewards to users for providing
liquidity to perpetual markets (handled by PerpRewardDistributor) or staking tokens (with the SafetyModule)

_Inherits from RewardController, which defines the RewardInfo data structure and functions allowing
governance to add/remove reward tokens or update their parameters, and implements IRewardContract, the
interface used by the ClearingHouse to update user rewards any time a user's position is updated_

## State Variables

### ecosystemReserve

Address of the reward token vault

```solidity
address public ecosystemReserve;
```

### rewardsAccruedByUser

Rewards accrued and not yet claimed by user

_First address is user, second is reward token_

```solidity
mapping(address => mapping(address => uint256)) public rewardsAccruedByUser;
```

### totalUnclaimedRewards

Total rewards accrued and not claimed by all users

_Address is reward token_

```solidity
mapping(address => uint256) public totalUnclaimedRewards;
```

### withdrawTimerStartByUserByMarket

Last timestamp when user withdrew liquidity from a market

_First address is user, second is the market_

```solidity
mapping(address => mapping(address => uint256)) public withdrawTimerStartByUserByMarket;
```

### lpPositionsPerUser

Latest LP/staking positions per user and market

_First address is user, second is the market_

```solidity
mapping(address => mapping(address => uint256)) public lpPositionsPerUser;
```

### cumulativeRewardPerLpToken

Reward accumulator for market rewards per reward token, as a number of reward tokens
per LP/staked token

_First address is reward token, second is the market_

```solidity
mapping(address => mapping(address => uint256)) public cumulativeRewardPerLpToken;
```

### cumulativeRewardPerLpTokenPerUser

Reward accumulator value per reward token when user rewards were last updated

_First address is user, second is reward token, third is the market_

```solidity
mapping(address => mapping(address => mapping(address => uint256))) public cumulativeRewardPerLpTokenPerUser;
```

### timeOfLastCumRewardUpdate

Timestamp of the most recent update to the per-market reward accumulator

```solidity
mapping(address => uint256) public timeOfLastCumRewardUpdate;
```

### totalLiquidityPerMarket

Total LP/staked tokens registered for rewards per market

```solidity
mapping(address => uint256) public totalLiquidityPerMarket;
```

## Functions

### constructor

RewardDistributor constructor

```solidity
constructor(address _ecosystemReserve) payable;
```

**Parameters**

| Name                | Type      | Description                                                             |
| ------------------- | --------- | ----------------------------------------------------------------------- |
| `_ecosystemReserve` | `address` | Address of the EcosystemReserve contract, which holds the reward tokens |

### updatePosition

Accrues rewards and updates the stored position of a user and the total liquidity of a market

_Executes whenever a user's position is updated for any reason_

```solidity
function updatePosition(address market, address user) external virtual;
```

**Parameters**

| Name     | Type      | Description                                                     |
| -------- | --------- | --------------------------------------------------------------- |
| `market` | `address` | Address of the market (i.e., perpetual market or staking token) |
| `user`   | `address` | Address of the user                                             |

### initMarketStartTime

Sets the start time for accruing rewards to a market which has not been initialized yet

_Can only be called by governance_

```solidity
function initMarketStartTime(address _market) external virtual onlyRole(GOVERNANCE);
```

**Parameters**

| Name      | Type      | Description                                                     |
| --------- | --------- | --------------------------------------------------------------- |
| `_market` | `address` | Address of the market (i.e., perpetual market or staking token) |

### addRewardToken

Adds a new reward token

_Can only be called by governance_

```solidity
function addRewardToken(
    address _rewardToken,
    uint88 _initialInflationRate,
    uint88 _initialReductionFactor,
    address[] calldata _markets,
    uint256[] calldata _marketWeights
) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                      | Type        | Description                                           |
| ------------------------- | ----------- | ----------------------------------------------------- |
| `_rewardToken`            | `address`   | Address of the reward token                           |
| `_initialInflationRate`   | `uint88`    | Initial inflation rate for the new token              |
| `_initialReductionFactor` | `uint88`    | Initial reduction factor for the new token            |
| `_markets`                | `address[]` | Addresses of the markets to reward with the new token |
| `_marketWeights`          | `uint256[]` | Initial weights per market for the new token          |

### removeRewardToken

Removes a reward token from all markets for which it is registered

_Can only be called by governance_

```solidity
function removeRewardToken(address _rewardToken) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name           | Type      | Description                           |
| -------------- | --------- | ------------------------------------- |
| `_rewardToken` | `address` | Address of the reward token to remove |

### setEcosystemReserve

Updates the address of the ecosystem reserve for storing reward tokens

_Can only be called by governance_

```solidity
function setEcosystemReserve(address _newEcosystemReserve) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                   | Type      | Description                          |
| ---------------------- | --------- | ------------------------------------ |
| `_newEcosystemReserve` | `address` | Address of the new ecosystem reserve |

### registerPositions

Fetches and stores the caller's LP/stake positions and updates the total liquidity in each of the
provided markets

_Can only be called once per user, only necessary if user was an LP prior to this contract's deployment_

```solidity
function registerPositions(address[] calldata _markets) external;
```

**Parameters**

| Name       | Type        | Description                           |
| ---------- | ----------- | ------------------------------------- |
| `_markets` | `address[]` | Addresses of the markets to sync with |

### claimRewardsFor

Accrues and then distributes rewards for all markets and reward tokens
and returns the amount of rewards that were not distributed to the given user

```solidity
function claimRewardsFor(address _user) public override;
```

**Parameters**

| Name    | Type      | Description                              |
| ------- | --------- | ---------------------------------------- |
| `_user` | `address` | Address of the user to claim rewards for |

### claimRewardsFor

Accrues and then distributes rewards for all markets and reward tokens
and returns the amount of rewards that were not distributed to the given user

```solidity
function claimRewardsFor(address _user, address[] memory _rewardTokens) public override nonReentrant whenNotPaused;
```

**Parameters**

| Name            | Type        | Description                              |
| --------------- | ----------- | ---------------------------------------- |
| `_user`         | `address`   | Address of the user to claim rewards for |
| `_rewardTokens` | `address[]` |                                          |

### \_updateMarketRewards

Updates the reward accumulator for a given market

_Executes when any of the following variables are changed: `inflationRate`, `marketWeights`, `liquidity`_

```solidity
function _updateMarketRewards(address market) internal override;
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `market` | `address` | Address of the market |

### \_accrueRewards

Accrues rewards to a user for a given market

_Assumes user's position hasn't changed since last accrual, since updating rewards due to changes in
position is handled by `updatePosition`_

```solidity
function _accrueRewards(address market, address user) internal virtual;
```

**Parameters**

| Name     | Type      | Description                                 |
| -------- | --------- | ------------------------------------------- |
| `market` | `address` | Address of the market to accrue rewards for |
| `user`   | `address` | Address of the user                         |

### \_distributeReward

Distributes accrued rewards from the ecosystem reserve to a user for a given reward token

_Checks if there are enough rewards remaining in the ecosystem reserve to distribute, updates
`totalUnclaimedRewards`, and returns the amount of rewards that were not distributed_

```solidity
function _distributeReward(address _token, address _to, uint256 _amount) internal returns (uint256);
```

**Parameters**

| Name      | Type      | Description                                  |
| --------- | --------- | -------------------------------------------- |
| `_token`  | `address` | Address of the reward token                  |
| `_to`     | `address` | Address of the user to distribute rewards to |
| `_amount` | `uint256` | Amount of rewards to distribute              |

**Returns**

| Name     | Type      | Description                                 |
| -------- | --------- | ------------------------------------------- |
| `<none>` | `uint256` | Amount of rewards that were not distributed |

### \_rewardTokenBalance

Gets the current balance of a reward token in the ecosystem reserve

```solidity
function _rewardTokenBalance(address _token) internal view returns (uint256);
```

**Parameters**

| Name     | Type      | Description                 |
| -------- | --------- | --------------------------- |
| `_token` | `address` | Address of the reward token |

**Returns**

| Name     | Type      | Description                                          |
| -------- | --------- | ---------------------------------------------------- |
| `<none>` | `uint256` | Balance of the reward token in the ecosystem reserve |

### \_registerPosition

```solidity
function _registerPosition(address _user, address _market) internal;
```

### \_getNumMarkets

Gets the number of markets to be used for reward distribution

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getNumMarkets() internal view virtual override returns (uint256);
```

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | Number of markets |

### \_getMarketAddress

Gets the address of a market at a given index

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getMarketAddress(uint256 idx) internal view virtual override returns (address);
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
function _getMarketIdx(uint256 i) internal view virtual override returns (uint256);
```

**Parameters**

| Name | Type      | Description                                                                                                                        |
| ---- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `i`  | `uint256` | Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule) |

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `uint256` | Index of the market in the market list |

### \_getCurrentPosition

Returns the current position of the user in the market (i.e., perpetual market or staked token)

```solidity
function _getCurrentPosition(address user, address market) internal view virtual override returns (uint256);
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
