# IPoolSwapStructs
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IWeightedPool.sol)


## Structs
### SwapRequest

```solidity
struct SwapRequest {
    IVault.SwapKind kind;
    IERC20 tokenIn;
    IERC20 tokenOut;
    uint256 amount;
    bytes32 poolId;
    uint256 lastChangeBlock;
    address from;
    address to;
    bytes userData;
}
```

