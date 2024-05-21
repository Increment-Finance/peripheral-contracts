import { parseUnits, parseEther } from "ethers";

export default {
  addresses: {
    USDC: "0xd88D19467f464e070Ebdb34a71D8b728CcE5E8c9",
    UA: "0x76e3E4B8E7ad3e072218501269d4c65AE080dC88",
    L2_GOVERNOR: "0x830c91140AD5851D5b765691e14c04101829Eaea",
    EMERGENCY_ADMIN: "0x830c91140AD5851D5b765691e14c04101829Eaea",
    CLEARING_HOUSE: "0x6C3388fc1dfa9733FeED87cD3639b463Ee072a8a",
    PERPETUALS: {
      ETHUSD: {
        PERPETUAL: "0x0F6CdB75CD0320942D8FDD1E92a711d7f5439516",
        VBASE: "0x0x3343b2ef3A237A5dE6E0F4e159C27d833081CED4",
        VQUOTE: "0x7d134dd523B0f2904C3F377f2a62d2b4cC90D185",
      },
    },
  },
  perpRewardParams: {
    initialInflationRate: parseEther("1171002.34"),
    initialReductionFactor: parseEther("1.189207115"),
    earlyWithdrawalThreshold: "864000", // 10 days
    rewardWeights: [parseUnits("75", 2), parseUnits("25", 2)], // Assumes two Perpetuals
  },
  smRewardParams: {
    initialInflationRate: parseEther("292750.59"),
    initialReductionFactor: parseEther("1.189207115"),
    maxMultiplier: parseUnits("4", 18),
    smoothingValue: parseUnits("30", 18),
    rewardWeights: [parseUnits("100", 2)], // Assumes only one StakedToken
  },
  stakedTokenParams: {
    cooldownSeconds: "864000", // 10 days
    unstakeWindow: "86400", // 1 day
    maxStakeAmount: parseEther("1000000"),
    name: "Staked UnderlyingToken", // Placeholder
    symbol: "stUT", // Placeholder
  },
};
