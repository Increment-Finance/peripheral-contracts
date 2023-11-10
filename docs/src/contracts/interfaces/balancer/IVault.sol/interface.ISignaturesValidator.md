# ISignaturesValidator
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IVault.sol)


## Functions
### getDomainSeparator

*Returns the EIP712 domain separator.*


```solidity
function getDomainSeparator() external view returns (bytes32);
```

### getNextNonce

*Returns the next nonce used by an address to sign messages.*


```solidity
function getNextNonce(address user) external view returns (uint256);
```

