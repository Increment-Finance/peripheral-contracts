# RewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/RewardDistributor.sol)

**Inherits:**
[IRewardDistributor](/contracts/interfaces/IRewardDistributor.sol/interface.IRewardDistributor.md), IStakingContract, [RewardController](/contracts/RewardController.sol/abstract.RewardController.md)

**Author:**
webthethird

Abstract contract responsible for accruing and distributing rewards to users for providing
liquidity to perpetual markets (handled by PerpRewardDistributor) or staking tokens (with the SafetyModule)

_Inherits from RewardController, which defines the RewardInfo data structure and functions allowing
governance to add/remove reward tokens or update their parameters, and implements IStakingContract, the
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

### lastDepositTimeByUserByMarket

Last timestamp when user withdrew liquidity from a market

_First address is user, second is the market_

```solidity
mapping(address => mapping(address => uint256)) public lastDepositTimeByUserByMarket;
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
constructor(address _ecosystemReserve);
```

**Parameters**

| Name                | Type      | Description                                                             |
| ------------------- | --------- | ----------------------------------------------------------------------- |
| `_ecosystemReserve` | `address` | Address of the EcosystemReserve contract, which holds the reward tokens |

### getNumMarkets

Gets the number of markets to be used for reward distribution

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getNumMarkets() public view virtual override returns (uint256);
```

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | Number of markets |

### getMaxMarketIdx

Gets the highest valid market index

```solidity
function getMaxMarketIdx() public view virtual override returns (uint256);
```

**Returns**

| Name     | Type      | Description                |
| -------- | --------- | -------------------------- |
| `<none>` | `uint256` | Highest valid market index |

### getMarketAddress

Gets the address of a market at a given index

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function getMarketAddress(uint256 idx) public view virtual override returns (address);
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
function getMarketIdx(uint256 i) public view virtual override returns (uint256);
```

**Parameters**

| Name | Type      | Description                                                                                                                        |
| ---- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `i`  | `uint256` | Index of the market in the allowlist `ClearingHouse.ids` (for the PerpRewardDistributor) or `stakingTokens` (for the SafetyModule) |

**Returns**

| Name     | Type      | Description                            |
| -------- | --------- | -------------------------------------- |
| `<none>` | `uint256` | Index of the market in the market list |

### getCurrentPosition

Returns the current position of the user in the market (i.e., perpetual market or staked token)

```solidity
function getCurrentPosition(address user, address market) public view virtual override returns (uint256);
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

### updateMarketRewards

Updates the reward accumulator for a given market

_Executes when any of the following variables are changed: `inflationRate`, `marketWeights`, `liquidity`_

```solidity
function updateMarketRewards(address market) public override;
```

**Parameters**

| Name     | Type      | Description           |
| -------- | --------- | --------------------- |
| `market` | `address` | Address of the market |

### updateStakingPosition

Accrues rewards and updates the stored position of a user and the total liquidity of a market

_Executes whenever a user's position is updated for any reason_

```solidity
function updateStakingPosition(address market, address user) external virtual;
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
function initMarketStartTime(address _market) external onlyRole(GOVERNANCE);
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
    uint256 _initialInflationRate,
    uint256 _initialReductionFactor,
    address[] calldata _markets,
    uint16[] calldata _marketWeights
) external nonReentrant onlyRole(GOVERNANCE);
```

**Parameters**

| Name                      | Type        | Description                                           |
| ------------------------- | ----------- | ----------------------------------------------------- |
| `_rewardToken`            | `address`   | Address of the reward token                           |
| `_initialInflationRate`   | `uint256`   | Initial inflation rate for the new token              |
| `_initialReductionFactor` | `uint256`   | Initial reduction factor for the new token            |
| `_markets`                | `address[]` | Addresses of the markets to reward with the new token |
| `_marketWeights`          | `uint16[]`  | Initial weights per market for the new token          |

### removeRewardToken

Removes a reward token from all markets for which it is registered

_Can only be called by governance_

```solidity
function removeRewardToken(address _rewardToken) external nonReentrant onlyRole(GOVERNANCE);
```

**Parameters**

| Name           | Type      | Description                           |
| -------------- | --------- | ------------------------------------- |
| `_rewardToken` | `address` | Address of the reward token to remove |

### setEcosystemReserve

Updates the address of the ecosystem reserve for storing reward tokens

_Can only be called by governance_

```solidity
function setEcosystemReserve(address _ecosystemReserve) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                | Type      | Description                          |
| ------------------- | --------- | ------------------------------------ |
| `_ecosystemReserve` | `address` | Address of the new ecosystem reserve |

### registerPositions

Fetches and stores the caller's LP/stake positions and updates the total liquidity in each market

_Can only be called once per user, only necessary if user was an LP/staker prior to this contract's deployment_

```solidity
function registerPositions() external nonReentrant;
```

### registerPositions

Fetches and stores the caller's LP/stake positions and updates the total liquidity in each market

_Can only be called once per user, only necessary if user was an LP/staker prior to this contract's deployment_

```solidity
function registerPositions(address[] calldata _markets) external nonReentrant;
```

**Parameters**

| Name       | Type         | Description                      |
| ---------- | ------------ | -------------------------------- |
| `_markets` | `address []` | Addresses of the markets to sync |

### claimRewards

Accrues and then distributes rewards for all markets to the caller

```solidity
function claimRewards() public override;
```

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
function claimRewardsFor(address _user, address _market) public override;
```

**Parameters**

| Name      | Type      | Description                                |
| --------- | --------- | ------------------------------------------ |
| `_user`   | `address` | Address of the user to claim rewards for   |
| `_market` | `address` | Address of the market to claim rewards for |

### claimRewardsFor

Accrues and then distributes rewards for all markets and reward tokens
and returns the amount of rewards that were not distributed to the given user

```solidity
function claimRewardsFor(address _user, address[] memory _rewardTokens) public override whenNotPaused;
```

**Parameters**

| Name            | Type        | Description                                         |
| --------------- | ----------- | --------------------------------------------------- |
| `_user`         | `address`   | Address of the user to claim rewards for            |
| `_rewardTokens` | `address[]` | Addresses of the reward tokens to claim rewards for |

### accrueRewards

Accrues rewards to a user for all markets

_Assumes user's position hasn't changed since last accrual, since updating rewards due to changes
in position is handled by `updateStakingPosition`_

```solidity
function accrueRewards(address user) external override;
```

**Parameters**

| Name   | Type      | Description                               |
| ------ | --------- | ----------------------------------------- |
| `user` | `address` | Address of the user to accrue rewards for |

### accrueRewards

Accrues rewards to a user for all markets

_Assumes user's position hasn't changed since last accrual, since updating rewards due to changes
in position is handled by `updateStakingPosition`_

```solidity
function accrueRewards(address market, address user) public virtual;
```

**Parameters**

| Name     | Type      | Description                                 |
| -------- | --------- | ------------------------------------------- |
| `market` | `address` | Address of the market to accrue rewards for |
| `user`   | `address` | Address of the user to accrue rewards for   |

### viewNewRewardAccrual

Returns the amount of rewards that would be accrued to a user for a given market

_Serves as a static version of `accrueRewards(address market, address user)`_

```solidity
function viewNewRewardAccrual(address market, address user) public view returns (uint256[] memory);
```

**Parameters**

| Name     | Type      | Description                                   |
| -------- | --------- | --------------------------------------------- |
| `market` | `address` | Address of the market to view new rewards for |
| `user`   | `address` | Address of the user                           |

**Returns**

| Name     | Type        | Description                                                                                             |
| -------- | ----------- | ------------------------------------------------------------------------------------------------------- |
| `<none>` | `uint256[]` | Amount of new rewards that would be accrued to the user for each reward token the given market receives |

### viewNewRewardAccrual

Returns the amount of rewards that would be accrued to a user for a given market

_Serves as a static version of `accrueRewards(address market, address user)`_

```solidity
function viewNewRewardAccrual(address market, address user, address rewardToken)
    public
    view
    virtual
    returns (uint256);
```

**Parameters**

| Name     | Type      | Description                                         |
| -------- | --------- | --------------------------------------------------- |
| `market` | `address` | Address of the market to view new rewards for       |
| `user`   | `address` | Address of the user                                 |
| `token`  | `address` | Address of the reward token to view new rewards for |

**Returns**

| Name     | Type      | Description                                                                                             |
| -------- | --------- | ------------------------------------------------------------------------------------------------------- |
| `<none>` | `uint256` | Amount of new rewards that would be accrued to the user for each reward token the given market receives |

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
