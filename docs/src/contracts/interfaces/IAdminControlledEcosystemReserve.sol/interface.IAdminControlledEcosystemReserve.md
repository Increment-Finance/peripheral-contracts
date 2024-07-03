# IAdminControlledEcosystemReserve
[Git Source](https://github.com/Increment-Finance/peripheral-contracts/blob/7b4166bd3bb6b2c678b84df162bcaf7af66b042d/contracts/interfaces/IAdminControlledEcosystemReserve.sol)


## Functions
### ETH_MOCK_ADDRESS

Returns the mock ETH reference address


```solidity
function ETH_MOCK_ADDRESS() external pure returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address The address|


### getFundsAdmin

Return the funds admin, only entity to be able to interact with this contract (controller of reserve)


```solidity
function getFundsAdmin() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address The address of the funds admin|


### approve

*Function for the funds admin to give ERC20 allowance to other parties*


```solidity
function approve(IERC20 token, address recipient, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`IERC20`|The address of the token to give allowance from|
|`recipient`|`address`|Allowance's recipient|
|`amount`|`uint256`|Allowance to approve|


### transfer

Function for the funds admin to transfer ERC20 tokens to other parties


```solidity
function transfer(IERC20 token, address recipient, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`IERC20`|The address of the token to transfer|
|`recipient`|`address`|Transfer's recipient|
|`amount`|`uint256`|Amount to transfer|


## Events
### NewFundsAdmin
Emitted when the funds admin changes


```solidity
event NewFundsAdmin(address indexed fundsAdmin);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fundsAdmin`|`address`|The new funds admin|

