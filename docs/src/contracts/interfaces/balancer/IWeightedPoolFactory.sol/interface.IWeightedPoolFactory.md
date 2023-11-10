# IWeightedPoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/balancer/IWeightedPoolFactory.sol)

**Inherits:**
[IBasePoolFactory](/src/interfaces/balancer/IWeightedPoolFactory.sol/interface.IBasePoolFactory.md)


## Functions
### create


```solidity
function create(
    string memory name,
    string memory symbol,
    address[] memory tokens,
    uint256[] memory normalizedWeights,
    address[] memory rateProviders,
    uint256 swapFeePercentage,
    address owner,
    bytes32 salt
) external returns (address);
```

