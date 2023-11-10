# IWeightedPoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IWeightedPoolFactory.sol)

**Inherits:**
[IBasePoolFactory](/contracts/interfaces/balancer/IWeightedPoolFactory.sol/interface.IBasePoolFactory.md)


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

