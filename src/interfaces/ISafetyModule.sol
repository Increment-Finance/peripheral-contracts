// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {IStakedToken} from "./IStakedToken.sol";

interface ISafetyModule {
    function vault() external view returns (address);
    function auctionModule() external view returns (address);
    function stakingTokens(uint256 i) external view returns (IStakedToken);
    function maxRewardMultiplier() external view returns (uint256);
    function smoothingValue() external view returns (uint256);

    function setMaxRewardMultiplier(uint256) external;
    function setSmoothingValue(uint256) external;
}
