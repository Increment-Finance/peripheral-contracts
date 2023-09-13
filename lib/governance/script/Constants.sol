// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.16;

address constant TOKEN_DEPLOYER = 0x3Da996c15Bc88f9F37BC520aBE78AB0fF82Bf62f;
address constant MULTI_SIG = 0x734d363e78f17e97b588205286Ea2ec1E75d27d8;

// Governance Settings
uint256 constant TOKEN_SUPPLY = 20_000_000 ether;
uint256 constant TIMELOCK_DURATION = 172800; /* 2 days */
string constant MERKLE_TREE_IPFS_HASH = "QmNLgpV9gE4a7sEA6YnseUvfhvx8cMiD4Ddhpdu251Y73W";

// Core Contributors: 12mo cliff, 48mo vesting
bytes constant CORE_CONTRIBUTOR_0 =
    abi.encode(0xEfB34b1BD6ca1D7607a16532dFA9E49bC7c36f2d, 1_000_000 ether, 365 days, 1460 days); // Core Contributor 1
bytes constant CORE_CONTRIBUTOR_1 =
    abi.encode(0x78603E49Ffd8958Eba61de3700F80AC734D54399, 1_000_000 ether, 365 days, 1460 days); // Core Contributor 2
bytes constant CORE_CONTRIBUTOR_2 = abi.encode(MULTI_SIG, 1_000_000 ether, 365 days, 1460 days); // Core Contributor 3

// Investors: 9mo cliff, 18mo vesting
bytes constant INVESTOR_0 = abi.encode(0x5028D77B91a3754fb38B2FBB726AF02d1FE44Db6, 1_200_000 ether, 274 days, 548 days);
bytes constant INVESTOR_1 = abi.encode(0x2d49A10d22A5d64a53F91E063Bd6BcF3D95c0663, 600_000 ether, 274 days, 548 days);
bytes constant INVESTOR_2 = abi.encode(0x8Ae4aA31C8D4cbBCdeF62fA2e301145bfd77F06B, 400_000 ether, 274 days, 548 days);
bytes constant INVESTOR_3 = abi.encode(0xA0F03d44F5DdC7450A7c3029974985c733833E3e, 400_000 ether, 274 days, 548 days);
bytes constant INVESTOR_4 = abi.encode(0x6A04941De896E4215Eeb8e6eb1b72AD2904D2402, 200_000 ether, 274 days, 548 days);
bytes constant INVESTOR_5 = abi.encode(0x0fe1CD1F62677cCd0501B4060d933740f58Fc3fe, 200_000 ether, 274 days, 548 days);

// Angels: 9mo cliff, 18mo vesting
bytes constant ANGEL_0 = abi.encode(0x445C770BFC3cDCC4f06E7A33f899B94F0b4063b9, 60_000 ether, 274 days, 548 days);
bytes constant ANGEL_1 = abi.encode(0xE6056F52719CbC225D7093B50180B4EACf024909, 20_000 ether, 274 days, 548 days);
bytes constant ANGEL_2 = abi.encode(0x2A99ADc0f1E302462124C70Af505415CE09A4fBb, 20_000 ether, 274 days, 548 days);
bytes constant ANGEL_3 = abi.encode(0x37Fbe4bDDf017C3a87B947547C05b6Fb34620B61, 20_000 ether, 274 days, 548 days);

// Development Fund: 48mo vesting, no cliff
bytes constant DEVELOPMENT_FUND = abi.encode(MULTI_SIG, 1_480_000 ether, 0 days, 1460 days); // Development Fund

// Ecosystem Fund: 24mo vesting, no cliff
bytes constant ECOSYSTEM_FUND =
    abi.encode(address(0), /* MUST be converted to Timelock address */ 800_000 ether, 0 days, 730 days); // Ecosystem
