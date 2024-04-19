// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.16;

// contracts
import "../../contracts/PerpRewardDistributor.sol";

contract TestPerpRewardDistributor is PerpRewardDistributor {
    constructor(
        uint88 _initialInflationRate,
        uint88 _initialReductionFactor,
        address _rewardToken,
        address _clearingHouse,
        address _ecosystemReserve,
        uint256 _earlyWithdrawalThreshold,
        uint256[] memory _initialRewardWeights
    )
        PerpRewardDistributor(
            _initialInflationRate,
            _initialReductionFactor,
            _rewardToken,
            _clearingHouse,
            _ecosystemReserve,
            _earlyWithdrawalThreshold,
            _initialRewardWeights
        )
    {}

    function accrueRewards(address user) external {
        uint256 numMarkets = _getNumMarkets();
        for (uint256 i; i < numMarkets;) {
            _accrueRewards(_getMarketAddress(_getMarketIdx(i)), user);
            unchecked {
                ++i;
            }
        }
    }
}
