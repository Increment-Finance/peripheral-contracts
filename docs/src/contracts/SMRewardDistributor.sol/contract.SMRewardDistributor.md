# SMRewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/50135f16a3332e293d1be01434556e7e68cc2f26/contracts/SMRewardDistributor.sol)

**Inherits:**
[RewardDistributor](/contracts/RewardDistributor.sol/abstract.RewardDistributor.md), [ISMRewardDistributor](/contracts/interfaces/ISMRewardDistributor.sol/interface.ISMRewardDistributor.md)

**Author:**
webthethird

Reward distributor for the Safety Module

## State Variables

### safetyModule

The SafetyModule contract which stores the list of StakedTokens and can call `updatePosition`

```solidity
ISafetyModule public safetyModule;
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

The starting timestamp used to calculate the user's reward multiplier for a given staking token

_First address is user, second is staking token_

```solidity
mapping(address => mapping(address => uint256)) public multiplierStartTimeByUser;
```

## Functions

### onlySafetyModule

Modifier for functions that should only be called by the SafetyModule

```solidity
modifier onlySafetyModule();
```

### constructor

SafetyModule constructor

```solidity
constructor(
    ISafetyModule _safetyModule,
    uint256 _maxRewardMultiplier,
    uint256 _smoothingValue,
    address _ecosystemReserve
) payable RewardDistributor(_ecosystemReserve);
```

**Parameters**

| Name                   | Type            | Description                                                                  |
| ---------------------- | --------------- | ---------------------------------------------------------------------------- |
| `_safetyModule`        | `ISafetyModule` | The address of the SafetyModule contract                                     |
| `_maxRewardMultiplier` | `uint256`       | The maximum reward multiplier, scaled by 1e18                                |
| `_smoothingValue`      | `uint256`       | The smoothing value, scaled by 1e18                                          |
| `_ecosystemReserve`    | `address`       | The address of the EcosystemReserve contract, where reward tokens are stored |

### updatePosition

Accrues rewards and updates the stored stake position of a user and the total tokens staked

_Executes whenever a user's stake is updated for any reason_

```solidity
function updatePosition(address market, address user)
    external
    virtual
    override(IRewardContract, RewardDistributor)
    onlySafetyModule;
```

**Parameters**

| Name     | Type      | Description                                     |
| -------- | --------- | ----------------------------------------------- |
| `market` | `address` | Address of the staking token in `stakingTokens` |
| `user`   | `address` | Address of the staker                           |

### paused

Indicates whether claiming rewards is currently paused

_Contract is paused if either this contract or the SafetyModule has been paused_

```solidity
function paused() public view override returns (bool);
```

**Returns**

| Name     | Type   | Description                     |
| -------- | ------ | ------------------------------- |
| `<none>` | `bool` | True if paused, false otherwise |

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

### initMarketStartTime

_Can only be called by the SafetyModule_

```solidity
function initMarketStartTime(address _market)
    external
    override(IRewardDistributor, RewardDistributor)
    onlySafetyModule;
```

**Parameters**

| Name      | Type      | Description                                                     |
| --------- | --------- | --------------------------------------------------------------- |
| `_market` | `address` | Address of the market (i.e., perpetual market or staking token) |

### setSafetyModule

Replaces the SafetyModule contract

_Only callable by governance_

```solidity
function setSafetyModule(ISafetyModule _newSafetyModule) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name               | Type            | Description                              |
| ------------------ | --------------- | ---------------------------------------- |
| `_newSafetyModule` | `ISafetyModule` | Address of the new SafetyModule contract |

### setMaxRewardMultiplier

Sets the maximum reward multiplier

_Only callable by governance, reverts if the new value is less than 1e18 (100%) or greater than 10e18 (1000%)_

```solidity
function setMaxRewardMultiplier(uint256 _maxRewardMultiplier) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name                   | Type      | Description                                   |
| ---------------------- | --------- | --------------------------------------------- |
| `_maxRewardMultiplier` | `uint256` | New maximum reward multiplier, scaled by 1e18 |

### setSmoothingValue

Sets the smoothing value used in calculating the reward multiplier

_Only callable by governance, reverts if the new value is less than 10e18 or greater than 100e18_

```solidity
function setSmoothingValue(uint256 _smoothingValue) external onlyRole(GOVERNANCE);
```

**Parameters**

| Name              | Type      | Description                         |
| ----------------- | --------- | ----------------------------------- |
| `_smoothingValue` | `uint256` | New smoothing value, scaled by 1e18 |

### pause

Pause the contract

_Only callable by governance_

```solidity
function pause() external override onlyRole(GOVERNANCE);
```

### unpause

Unpause the contract

_Only callable by governance_

```solidity
function unpause() external override onlyRole(GOVERNANCE);
```

### \_getNumMarkets

```solidity
function _getNumMarkets() internal view virtual override returns (uint256);
```

### \_getMarketAddress

```solidity
function _getMarketAddress(uint256 index) internal view virtual override returns (address);
```

### \_getMarketIdx

```solidity
function _getMarketIdx(uint256 i) internal view virtual override returns (uint256);
```

### \_getCurrentPosition

Returns the user's staking token balance

```solidity
function _getCurrentPosition(address staker, address token) internal view virtual override returns (uint256);
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

### \_accrueRewards

Accrues rewards to a user for a given staking token

_Assumes stake position hasn't changed since last accrual, since updating rewards due to changes in
stake position is handled by `updatePosition`_

```solidity
function _accrueRewards(address market, address user) internal virtual override;
```

**Parameters**

| Name     | Type      | Description                             |
| -------- | --------- | --------------------------------------- |
| `market` | `address` | Address of the token in `stakingTokens` |
| `user`   | `address` | Address of the user                     |
