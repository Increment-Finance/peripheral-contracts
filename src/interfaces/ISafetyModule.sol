// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import {IStakedToken} from "./IStakedToken.sol";
import {IStakingContract} from "increment-protocol/interfaces/IStakingContract.sol";

interface ISafetyModule is IStakingContract {
    error SafetyModule_CallerIsNotStakingToken(address caller);
    error SafetyModule_StakingTokenAlreadyRegistered(address stakingToken);
    error SafetyModule_InvalidStakingToken(address stakingToken);

    function vault() external view returns (address);

    function auctionModule() external view returns (address);

    function stakingTokens(uint256 i) external view returns (IStakedToken);

    function maxRewardMultiplier() external view returns (uint256);

    function smoothingValue() external view returns (uint256);

    function getStakingTokenIdx(address) external view returns (uint256);

    function setMaxRewardMultiplier(uint256) external;

    function setSmoothingValue(uint256) external;
}
