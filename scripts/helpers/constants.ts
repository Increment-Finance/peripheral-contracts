import { parseUnits, parseEther } from "ethers";

export default {
  addresses: {
    USDC: "0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4",
    UA: "0xfc840c55b791a1DbAF5C588116a8fC0b4859d227",
    L2_GOVERNOR: "0x00000000000000000000000000000000deadbeef",
    L2_TOKEN: "0xb2c5a37A4C37c16DDd21181F6Ddbc989c3D36cDC",
    UNDERLYING_TOKEN: "0x00000000000000000000000000000000deadbeef",
    EMERGENCY_ADMIN: "0x4f05E10B7e60D5b18c38a723d9469b4962C288D9",
    CLEARING_HOUSE: "0x9200536A28b0Bf5d02b7d8966cd441EDc173dE61",
    PERPETUALS: {
      ETHUSD: {
        PERPETUAL: "0xeda91B6d87A257d209e947BD7f1bC25FC49272B6",
        VBASE: "0xFF4Dd1A9839065885d3313Ca525aC35213af69C5",
        VQUOTE: "0x9a2658635e7000231e1480F2112e5c7d67F8e486",
      },
    },
  },
  perpRewardParams: {
    initialInflationRate: parseEther("1171002.34"),
    initialReductionFactor: parseEther("1.189207115"),
    earlyWithdrawalThreshold: "864000", // 10 days
    rewardWeights: [parseUnits("100", 2)],
  },
  smRewardParams: {
    initialInflationRate: parseEther("292750.59"),
    initialReductionFactor: parseEther("1.189207115"),
    maxMultiplier: parseUnits("4", 18),
    smoothingValue: parseUnits("30", 18),
    rewardWeights: [parseUnits("100", 2)],
  },
  stakedTokenParams: {
    cooldownSeconds: "864000", // 10 days
    unstakeWindow: "86400", // 1 day
    maxStakeAmount: parseEther("1000000"),
    name: "Staked <UNDERLYING TOKEN NAME>",
    symbol: "st<UNDERLYING TOKEN SYMBOL>",
  },
};
