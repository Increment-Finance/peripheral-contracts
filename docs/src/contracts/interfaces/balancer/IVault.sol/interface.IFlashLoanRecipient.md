# IFlashLoanRecipient
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/fc86e744c6664e8852ac82787aa2f73b160e6a5d/contracts/interfaces/balancer/IVault.sol)


## Functions
### receiveFlashLoan

*When `flashLoan` is called on the Vault, it invokes the `receiveFlashLoan` hook on the recipient.
At the time of the call, the Vault will have transferred `amounts` for `tokens` to the recipient. Before this
call returns, the recipient must have transferred `amounts` plus `feeAmounts` for each token back to the
Vault, or else the entire flash loan will revert.
`userData` is the same value passed in the `IVault.flashLoan` call.*


```solidity
function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
) external;
```

