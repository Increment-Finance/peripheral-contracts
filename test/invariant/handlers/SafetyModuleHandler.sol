// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// contracts
import "../../../contracts/SafetyModule.sol";
import "../../../contracts/StakedToken.sol";
import {Test} from "forge/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ITestContract {
    function addStakedToken(StakedToken stakedToken) external;
}

contract SafetyModuleHandler is Test {
    SafetyModule public safetyModule;

    ITestContract public testContract;

    address public governance;

    modifier useGovernance() {
        vm.startPrank(governance);
        _;
        vm.stopPrank();
    }

    constructor(SafetyModule _safetyModule, address _governance) {
        safetyModule = _safetyModule;
        governance = _governance;
        testContract = ITestContract(msg.sender);
    }

    /* ******************** */
    /* Governance Functions */
    /* ******************** */

    function addStakingToken(
        string memory underlyingName,
        string memory underlyingSymbol,
        uint256 cooldownSeconds,
        uint256 unstakeWindowSeconds,
        uint256 maxStakeAmount
    ) external useGovernance {
        cooldownSeconds = bound(cooldownSeconds, 1 hours, 1 weeks);
        unstakeWindowSeconds = bound(unstakeWindowSeconds, 1 hours, 1 weeks);
        maxStakeAmount = bound(maxStakeAmount, 10_000e18, 1_000_000e18);
        ERC20 underlying = new ERC20(underlyingName, underlyingSymbol);
        StakedToken stakedToken = new StakedToken(
            underlying,
            safetyModule,
            cooldownSeconds,
            unstakeWindowSeconds,
            maxStakeAmount,
            "stk".concat(underlyingName),
            "stk".concat(underlyingSymbol)
        );
        safetyModule.addStakedToken(stakedToken);
        testContract.addStakedToken(stakedToken);
    }
}
