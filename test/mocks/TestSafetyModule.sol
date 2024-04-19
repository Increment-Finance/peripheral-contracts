// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

import {SafetyModule} from "../../contracts/SafetyModule.sol";
import {IStakedToken} from "../../contracts/interfaces/IStakedToken.sol";

contract TestSafetyModule is SafetyModule {
    constructor(address _auctionModule, address _smRewardDistributor, address _governance)
        SafetyModule(_auctionModule, _smRewardDistributor, _governance)
    {}

    function returnFunds(address _stakedToken, address _from, uint256 _amount) external onlyRole(GOVERNANCE) {
        IStakedToken stakedToken = stakedTokens[getStakedTokenIdx(_stakedToken)];
        _returnFunds(stakedToken, _from, _amount);
    }
}
