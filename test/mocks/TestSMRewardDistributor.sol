// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../contracts/SMRewardDistributor.sol";

contract TestSMRewardDistributor is SMRewardDistributor {

    constructor(
        ISafetyModule _safetyModule,
        uint256 _maxRewardMultiplier,
        uint256 _smoothingValue,
        address _ecosystemReserve
    ) SMRewardDistributor(
        _safetyModule,
        _maxRewardMultiplier,
        _smoothingValue,
        _ecosystemReserve
    ) {}

    function accrueRewards(address user) external {
        uint256 numMarkets = _getNumMarkets();
        for (uint i; i < numMarkets; ++i) {
            _accrueRewards(_getMarketAddress(_getMarketIdx(i)), user);
        }
    }

    function accrueRewards(address market, address user) external {
        _accrueRewards(market, user);
    }
}