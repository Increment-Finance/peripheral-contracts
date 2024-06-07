import { parseUnits, parseEther } from "ethers";

export default {
  addresses: {
    USDC: "0xd88D19467f464e070Ebdb34a71D8b728CcE5E8c9",
    UA: "0x0252Cc0C06ae36A5Fafb8324AeB7D87597d03814",
    L2_GOVERNOR: "0x4E39DCdac1DCa1694897B5CB783Ab52683586962", // EOA owned by webthethird
    EMERGENCY_ADMIN: "0x4E39DCdac1DCa1694897B5CB783Ab52683586962", // EOA owned by webthethird
    CLEARING_HOUSE: "0xEb6cdC125EBeCa67233868580E8d70effEa07Ea6",
    PERPETUALS: {
      ETHUSD: {
        PERPETUAL: "0xc1a193559cEAE24e8d68c4C38bB1BCE882aBc14B",
        VBASE: "0x4f37d168e211391DfdE64543ED96145567D987A4",
        VQUOTE: "0x774B7751099f232A7ee819eC2d75C3969a1e9FCd",
      },
    },
    ECOSYSTEM_RESERVE: "0xF965EC5f489af2fE27321BD6b09974299Fd8D42b",
    SAFETY_MODULE: "0x4e4fb21C5723C40c7183e5dF6cdf0b4130Fc549A",
    SM_REWARD_DISTRIBUTOR: "0x2545218d22FE270e6BAd4733452c3053154e3aE2",
    PERP_REWARD_DISTRIBUTOR: "0x0D7125050d2515C6d00D41AA2e3a753Ff88Ed8cC",
    STAKED_TOKENS: {
      UT: {
        STAKED_TOKEN: "0x4F540A4046999288fc327dfca98dfB0d37bD0002",
        UNDERLYING_TOKEN: "0x5A1aa3EEe4532e34Af4F233e20b896f80b544803",
      },
      CSLP: {
        STAKED_TOKEN: "0xaAf9e83374f69eEC9ECfE0fB89216882dA34FaBf",
        UNDERLYING_TOKEN: "0xF21466C2b3f84b3298b911E02F5E5766B44F3a9f",
      },
    },
    REWARD_TOKENS: {
      INCR: "0xbE5Cb83E20b4F9fF6c1bB38bB588898e22add68F",
      USDC: "0xd88D19467f464e070Ebdb34a71D8b728CcE5E8c9",
    },
  },
  perpRewardParams: {
    initialInflationRate: parseEther("1171002.34"),
    initialReductionFactor: parseEther("1.189207115"),
    earlyWithdrawalThreshold: "864000", // 10 days
    rewardWeights: [parseUnits("100", 2)], // Assumes only one Perpetuals
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
