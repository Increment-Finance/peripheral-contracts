# IProtocolFeesCollector
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IVault.sol)


## Functions
### withdrawCollectedFees


```solidity
function withdrawCollectedFees(IERC20[] calldata tokens, uint256[] calldata amounts, address recipient) external;
```

### setSwapFeePercentage


```solidity
function setSwapFeePercentage(uint256 newSwapFeePercentage) external;
```

### setFlashLoanFeePercentage


```solidity
function setFlashLoanFeePercentage(uint256 newFlashLoanFeePercentage) external;
```

### getSwapFeePercentage


```solidity
function getSwapFeePercentage() external view returns (uint256);
```

### getFlashLoanFeePercentage


```solidity
function getFlashLoanFeePercentage() external view returns (uint256);
```

### getCollectedFeeAmounts


```solidity
function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts);
```

### getAuthorizer


```solidity
function getAuthorizer() external view returns (IAuthorizer);
```

### vault


```solidity
function vault() external view returns (IVault);
```

## Events
### SwapFeePercentageChanged

```solidity
event SwapFeePercentageChanged(uint256 newSwapFeePercentage);
```

### FlashLoanFeePercentageChanged

```solidity
event FlashLoanFeePercentageChanged(uint256 newFlashLoanFeePercentage);
```

