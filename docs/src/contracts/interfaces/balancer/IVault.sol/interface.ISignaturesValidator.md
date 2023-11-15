# ISignaturesValidator
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/45559668fd9e29384d52be9948eb4e35f7e92b00/contracts/interfaces/balancer/IVault.sol)


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

