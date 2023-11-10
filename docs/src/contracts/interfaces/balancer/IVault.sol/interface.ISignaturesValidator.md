# ISignaturesValidator
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/b10b7c737f1995b97150c4bde2bb1f9387e53eef/src/interfaces/balancer/IVault.sol)


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

