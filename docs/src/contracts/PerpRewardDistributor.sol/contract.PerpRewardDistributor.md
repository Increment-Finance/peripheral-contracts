# PerpRewardDistributor

[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/ecb136b3c508e89c22b16cec8dcfd7e319381983/contracts/PerpRewardDistributor.sol)

**Inherits:**
[RewardDistributor](/contracts/RewardDistributor.sol/abstract.RewardDistributor.md), [IPerpRewardDistributor](/contracts/interfaces/IPerpRewardDistributor.sol/interface.IPerpRewardDistributor.md)

**Author:**
webthethird

Handles reward accrual and distribution for liquidity providers in Perpetual markets

## State Variables

### clearingHouse

Clearing House contract

```solidity
IClearingHouse public clearingHouse;
```

### earlyWithdrawalThreshold

Amount of time after which LPs can remove liquidity without penalties

```solidity
uint256 public override earlyWithdrawalThreshold;
```

## Functions

### onlyClearingHouse

Modifier for functions that can only be called by the ClearingHouse, i.e., `updateStakingPosition`

```solidity
modifier onlyClearingHouse();
```

### constructor

PerpRewardDistributor constructor

```solidity
constructor(
    uint256 _initialInflationRate,
    uint256 _initialReductionFactor,
    address _rewardToken,
    address _clearingHouse,
    address _ecosystemReserve,
    uint256 _earlyWithdrawalThreshold,
    uint16[] memory _initialRewardWeights
) RewardDistributor(_ecosystemReserve);
```

**Parameters**

| Name                        | Type       | Description                                                                    |
| --------------------------- | ---------- | ------------------------------------------------------------------------------ |
| `_initialInflationRate`     | `uint256`  | The initial inflation rate for the first reward token, scaled by 1e18          |
| `_initialReductionFactor`   | `uint256`  | The initial reduction factor for the first reward token, scaled by 1e18        |
| `_rewardToken`              | `address`  | The address of the first reward token                                          |
| `_clearingHouse`            | `address`  | The address of the ClearingHouse contract, which calls `updateStakingPosition` |
| `_ecosystemReserve`         | `address`  | The address of the EcosystemReserve contract, which stores reward tokens       |
| `_earlyWithdrawalThreshold` | `uint256`  | The amount of time after which LPs can remove liquidity without penalties      |
| `_initialRewardWeights`     | `uint16[]` | The initial reward weights for the first reward token, as basis points         |

### updateStakingPosition

Accrues rewards and updates the stored LP position of a user and the total LP of a market

_Executes whenever a user's liquidity is updated for any reason_

```solidity
function updateStakingPosition(address market, address user) external virtual override nonReentrant onlyClearingHouse;
```

**Parameters**

| Name     | Type      | Description                      |
| -------- | --------- | -------------------------------- |
| `market` | `address` | Address of the perpetual market  |
| `user`   | `address` | Address of the liquidity provier |

### accrueRewards

Accrues rewards to a user for a given market

_Assumes LP position hasn't changed since last accrual, since updating rewards due to changes in
LP position is handled by `updateStakingPosition`_

```solidity
function accrueRewards(address market, address user) public virtual override nonReentrant;
```

**Parameters**

| Name     | Type      | Description                                         |
| -------- | --------- | --------------------------------------------------- |
| `market` | `address` | Address of the market in `ClearingHouse.perpetuals` |
| `user`   | `address` | Address of the user                                 |

### paused

Indicates whether claiming rewards is currently paused

_Contract is paused if either this contract or the ClearingHouse has been paused_

```solidity
function paused() public view override returns (bool);
```

**Returns**

| Name     | Type   | Description                     |
| -------- | ------ | ------------------------------- |
| `<none>` | `bool` | True if paused, false otherwise |

### \_getNumMarkets

Gets the number of markets to be used for reward distribution

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getNumMarkets() internal view override returns (uint256);
```

**Returns**

| Name     | Type      | Description       |
| -------- | --------- | ----------------- |
| `<none>` | `uint256` | Number of markets |

### \_getMarketAddress

Gets the address of a market at a given index

_Markets are the perpetual markets (for the PerpRewardDistributor) or staked tokens (for the SafetyModule)_

```solidity
function _getMarketAddress(uint256 idx) internal view override returns (address);
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
function _getMarketIdx(uint256 i) internal view override returns (uint256);
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
function _getCurrentPosition(address user, address market) internal view override returns (uint256);
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
