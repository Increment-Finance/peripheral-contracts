import {
  parseUnits,
  ZeroAddress,
  MaxUint256,
  Contract,
  Interface,
} from "ethers";
import * as hre from "hardhat";

import { getWallet } from "./helpers/utils";
import constants from "./helpers/constants.sepolia";

export default async function () {
  const wallet = getWallet();

  const usdc = constants.addresses.USDC;

  const SMRD_Artifact = await hre.artifacts.readArtifact("SMRewardDistributor");
  const smRewardDistributor = new Contract(
    constants.addresses.SM_REWARD_DISTRIBUTOR,
    SMRD_Artifact.abi,
    wallet
  );
  const stakedTokenAddresses = [
    constants.addresses.STAKED_TOKENS.UT.STAKED_TOKEN,
    constants.addresses.STAKED_TOKENS.CSLP.STAKED_TOKEN,
  ];

  console.log(`Adding reward token ${usdc} to SMRD...`);
  await smRewardDistributor
    .addRewardToken(
      usdc,
      parseUnits("1000", 6),
      constants.smRewardParams.initialReductionFactor,
      stakedTokenAddresses,
      [parseUnits("50", 2), parseUnits("50", 2)]
    )
    .then((tx) => tx.wait());
}
