# SafetyModule

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/SafetyModule.sol)

**Inherits:**
[ISafetyModule](/src/interfaces/ISafetyModule.sol/interface.ISafetyModule.md), [RewardDistributor](/src/RewardDistributor.sol/abstract.RewardDistributor.md)

**Author:**
webthethird

Handles reward accrual and distribution for staking tokens, and allows governance to auction a
percentage of user funds in the event of an insolvency in the vault

_Auction module and related logic is not yet implemented_

## State Variables

### vault

Address of the Increment vault contract, where funds are sent in the event of an auction

```solidity
address public vault;
```

### auctionModule

Address of the auction module, which sells user funds in the event of an insolvency

```solidity
address public auctionModule;
```

### stakingTokens

Array of staking tokens that are registered with the SafetyModule

```solidity
IStakedToken[] public stakingTokens;
```

### maxPercentUserLoss

The maximum percentage of user funds that can be sold at auction, normalized to 1e18

```solidity
uint256 public maxPercentUserLoss;
```

### maxRewardMultiplier

The maximum reward multiplier, scaled by 1e18

```solidity
uint256 public maxRewardMultiplier;
```

### smoothingValue

The smoothing value, scaled by 1e18

_The higher the value, the slower the multiplier approaches its max_

```solidity
uint256 public smoothingValue;
```

### multiplierStartTimeByUser

Stores the timestamp of the first deposit or most recent withdrawal

_First address is user, second is staking token_

```solidity
mapping(address => mapping(address => uint256)) public multiplierStartTimeByUser;
```

## Functions

### onlyStakingToken

Modifier for functions that can only be called by a registered StakedToken contract,
i.e., `updateStakingPosition`

```solidity
modifier onlyStakingToken();
```

### constructor

SafetyModule constructor

```solidity
constructor(
    address _vault,
    address _auctionModule,
    uint256 _maxPercentUserLoss,
    uint256 _maxRewardMultiplier,
    uint256 _smoothingValue,
    address _ecosystemReserve
) RewardDistributor(_ecosystemReserve);
```

**Parameters**

| Name                   | Type      | Description                                                                              |
| ---------------------- | --------- | ---------------------------------------------------------------------------------------- |
| `_vault`               | `address` | Address of the Increment vault contract, where funds are sent in the event of an auction |
| `_auctionModule`       | `address` | Address of the auction module, which sells user funds in the event of an insolvency      |
| `_maxPercentUserLoss`  | `uint256` | The max percentage of user funds that can be sold at auction, normalized to 1e18         |
| `_maxRewardMultiplier` | `uint256` | The maximum reward multiplier, scaled by 1e18                                            |
| `_smoothingValue`      | `uint256` | The smoothing value, scaled by 1e18                                                      |
| `_ecosystemReserve`    | `address` | The address of the EcosystemReserve contract, where reward tokens are stored             |

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

### getStakingTokenIdx

Returns the index of the staking token in the `stakingTokens` array

_Reverts with `SafetyModule_InvalidStakingToken` if the staking token is not registered_

```solidity
function getStakingTokenIdx(address token) public view returns (uint256);
```

**Parameters**

| Name    | Type      | Description                  |
| ------- | --------- | ---------------------------- |
| `token` | `address` | Address of the staking token |

**Returns**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `<none>` | `uint256` | Index of the staking token in the `stakingTokens` array |

### getCurrentPosition

Returns the user's staking token balance

```solidity
function getCurrentPosition(address staker, address token) public view virtual override returns (uint256);
```

**Parameters**

| Name     | Type      | Description                  |
| -------- | --------- | ---------------------------- |
| `staker` | `address` | Address of the user          |
| `token`  | `address` | Address of the staking token |

**Returns**

| Name     | Type      | Description                                      |
| -------- | --------- | ------------------------------------------------ |
| `<none>` | `uint256` | Current balance of the user in the staking token |

### getAuctionableBalance

Returns the amount of the user's staking tokens that can be sold at auction in the event of
an insolvency in the vault that cannot be covered by the insurance fund

```solidity
function getAuctionableBalance(address staker, address token) public view virtual returns (uint256);
```

**Parameters**

| Name     | Type      | Description                  |
| -------- | --------- | ---------------------------- |
| `staker` | `address` | Address of the user          |
| `token`  | `address` | Address of the staking token |

**Returns**

| Name     | Type      | Description                                              |
| -------- | --------- | -------------------------------------------------------- |
| `<none>` | `uint256` | Balance of the user multiplied by the maxPercentUserLoss |

### updateStakingPosition

Accrues rewards and updates the stored stake position of a user and the total tokens staked

_Executes whenever a user's stake is updated for any reason_

```solidity
function updateStakingPosition(address market, address user)
    external
    virtual
    override(IStakingContract, RewardDistributor)
    nonReentrant
    onlyStakingToken;
```

**Parameters**

| Name     | Type      | Description                                     |
| -------- | --------- | ----------------------------------------------- |
| `market` | `address` | Address of the staking token in `stakingTokens` |
| `user`   | `address` | Address of the staker                           |

### accrueRewards

newRewards = user.lpBalance x (global.cumRewardPerLpToken - user.cumRewardPerLpToken) x user.rewardMultiplier

Accrues rewards to a user for a given staking token

_Assumes stake position hasn't changed since last accrual, since updating rewards due to changes in
stake position is handled by `updateStakingPosition`_

```solidity
function accrueRewards(address market, address user) public virtual override nonReentrant;
```

**Parameters**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `market` | `address` | Address of the token in `stakingTokens` |
| `user`   | `address` | Address of the user                     |

### viewNewRewardAccrual

Returns the amount of new rewards that would be accrued to a user by calling `accrueRewards`
for a given market and reward token

```solidity
function viewNewRewardAccrual(address market, address user, address token) public view override returns (uint256);
```

**Parameters**

| Name     | Type      | Description                                     |
| -------- | --------- | ----------------------------------------------- |
| `market` | `address` | Address of the staking token in `stakingTokens` |
| `user`   | `address` | Address of the user                             |
| `token`  | `address` | Address of the reward token                     |

**Returns**

| Name     | Type      | Description                                             |
| -------- | --------- | ------------------------------------------------------- |
| `<none>` | `uint256` | Amount of new rewards that would be accrued to the user |

### computeRewardMultiplier

Computes the user's reward multiplier for the given staking token

_Based on the max multiplier, smoothing factor and time since last withdrawal (or first deposit)_

```solidity
function computeRewardMultiplier(address _user, address _stakingToken) public view returns (uint256);
```

**Parameters**

| Name            | Type      | Description                              |
| --------------- | --------- | ---------------------------------------- |
| `_user`         | `address` | Address of the staker                    |
| `_stakingToken` | `address` | Address of staking token earning rewards |

**Returns**

| Name     | Type      | Description                              |
| -------- | --------- | ---------------------------------------- |
| `<none>` | `uint256` | User's reward multiplier, scaled by 1e18 |

### setMaxPercentUserLoss

Sets the maximum percentage of user funds that can be sold at auction, normalized to 1e18

_Only callable by governance, reverts if the new value is greater than 1e18, i.e., 100%_

```solidity
function setMaxPercentUserLoss(uint256 _maxPercentUserLoss) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                  | Type      | Description                                                                          |
| --------------------- | --------- | ------------------------------------------------------------------------------------ |
| `_maxPercentUserLoss` | `uint256` | New maximum percentage of user funds that can be sold at auction, normalized to 1e18 |

### setMaxRewardMultiplier

Sets the maximum reward multiplier, normalized to 1e18

_Only callable by governance, reverts if the new value is less than 1e18 (100%) or greater than 10e18 (1000%)_

```solidity
function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                   | Type      | Description                                       |
| ---------------------- | --------- | ------------------------------------------------- |
| `_maxRewardMultiplier` | `uint256` | New maximum reward multiplier, normalized to 1e18 |

### setSmoothingValue

Sets the smoothing value used in calculating the reward multiplier, normalized to 1e18

_Only callable by governance, reverts if the new value is less than 10e18 or greater than 100e18_

```solidity
function setSmoothingValue(uint256 _smoothingValue) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name              | Type      | Description                             |
| ----------------- | --------- | --------------------------------------- |
| `_smoothingValue` | `uint256` | New smoothing value, normalized to 1e18 |

### addStakingToken

Adds a new staking token to the SafetyModule's stakingTokens array

_Only callable by governance, reverts if the staking token is already registered_

```solidity
function addStakingToken(IStakedToken _stakingToken) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name            | Type           | Description                      |
| --------------- | -------------- | -------------------------------- |
| `_stakingToken` | `IStakedToken` | Address of the new staking token |
