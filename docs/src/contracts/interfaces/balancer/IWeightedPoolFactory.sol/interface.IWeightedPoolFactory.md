# IWeightedPoolFactory
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IWeightedPoolFactory.sol)

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

