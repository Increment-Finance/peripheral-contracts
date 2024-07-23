import {
  parseEther,
  ZeroAddress,
  MaxUint256,
  Contract,
  Interface,
} from "ethers";
import * as hre from "hardhat";

import { deployContract, getWallet } from "./helpers/utils";
import constants from "./helpers/constants";

export default async function () {
  const wallet = getWallet();
  const deployerAddress = await wallet.getAddress();
  const rewardTokenAddress = constants.addresses.L2_TOKEN;
  const governorAddress = constants.addresses.L2_GOVERNOR;

  // 1. Deploy EcosystemReserve
  const ecosystemReserve = await deployContract("EcosystemReserve", [
    deployerAddress,
  ]);
  const ecosystemReserveAddress = await ecosystemReserve.getAddress();

  // 2. Deploy SafetyModule
  const safetyModule = await deployContract("SafetyModule", [
    ZeroAddress,
    ZeroAddress,
    governorAddress,
  ]);
  const safetyModuleAddress = await safetyModule.getAddress();

  // 3. Deploy AuctionModule and add it to the SafetyModule
  const auctionModule = await deployContract("AuctionModule", [
    safetyModuleAddress,
    constants.addresses.USDC,
  ]);
  const auctionModuleAddress = await auctionModule.getAddress();
  await safetyModule
    .setAuctionModule(auctionModuleAddress)
    .then((tx) => tx.wait());

  // 4. Deploy SMRewardDistributor and add it to the SafetyModule
  const smRewardDistributor = await deployContract("SMRewardDistributor", [
    safetyModuleAddress,
    constants.smRewardParams.maxMultiplier,
    constants.smRewardParams.smoothingValue,
    ecosystemReserveAddress,
  ]);
  const smRewardDistributorAddress = await smRewardDistributor.getAddress();
  await safetyModule
    .setRewardDistributor(smRewardDistributorAddress)
    .then((tx) => tx.wait());

  // 5. Deploy StakedToken and add it to the SafetyModule
  const stakedToken = await deployContract("StakedToken", [
    constants.addresses.UNDERLYING_TOKEN,
    safetyModuleAddress,
    constants.stakedTokenParams.cooldownSeconds,
    constants.stakedTokenParams.unstakeWindow,
    constants.stakedTokenParams.maxStakeAmount,
    constants.stakedTokenParams.name,
    constants.stakedTokenParams.symbol,
  ]);
  const stakedTokenAddress = await stakedToken.getAddress();
  await safetyModule.addStakedToken(stakedTokenAddress).then((tx) => tx.wait());

  // 6. Add reward token to SMRewardDistributor
  console.log(`Adding reward token ${rewardTokenAddress} to SMRD...`);
  await smRewardDistributor
    .addRewardToken(
      rewardTokenAddress,
      constants.smRewardParams.initialInflationRate,
      constants.smRewardParams.initialReductionFactor,
      [stakedTokenAddress],
      constants.smRewardParams.rewardWeights
    )
    .then((tx) => tx.wait());

  // 7. Approve SMRewardDistributor to transfer INCR tokens from the EcosystemReserve
  console.log(
    "Approving SM reward distributor to transfer reward tokens from EcosystemReserve..."
  );
  await ecosystemReserve
    .approve(rewardTokenAddress, smRewardDistributorAddress, MaxUint256)
    .then((tx) => tx.wait());

  // 8. Transfer EcosystemReserve admin role to the L2 governor
  await ecosystemReserve.transferAdmin(governorAddress).then((tx) => tx.wait());

  // 9. Grant/renounce GOVERNANCE and EMERGENCY_ADMIN roles for:
  //     - SafetyModule
  //     - AuctionModule
  //     - SMRewardDistributor
  //     - StakedToken
  const governanceRole = await safetyModule.GOVERNANCE();
  const emergencyAdminRole = await safetyModule.EMERGENCY_ADMIN();
  const roles = [
    {
      roleId: emergencyAdminRole,
      roleName: "EMERGENCY_ADMIN",
      recipient: constants.addresses.EMERGENCY_ADMIN,
    },
    {
      roleId: governanceRole,
      roleName: "GOVERNANCE",
      recipient: governorAddress,
    },
  ];
  const contracts = [
    {
      contract: safetyModule,
      contractName: "SafetyModule",
    },
    {
      contract: auctionModule,
      contractName: "AuctionModule",
    },
    {
      contract: smRewardDistributor,
      contractName: "SMRewardDistributor",
    },
    {
      contract: stakedToken,
      contractName: "StakedToken",
    },
  ];
  for (const { contract, contractName } of contracts) {
    for (const { roleId, roleName, recipient } of roles) {
      console.log(
        `Granting role ${roleName} for contract ${contractName} to ${recipient}...`
      );
      await contract
        .grantRole(roleId, recipient)
        .then(async (tx) => {
          tx.wait();
          console.log(
            `Renouncing role ${roleName} for contract ${contractName} from deployer...`
          );
          await contract
            .renounceRole(roleId, deployerAddress)
            .then((tx) => tx.wait())
            .catch(() => {
              console.log(
                `Failed to renounce ${roleName} role for ${contractName} contract`
              );
            });
        })
        .catch(() => {
          console.log(
            `Failed to grant ${roleName} role for ${contractName} contract`
          );
        });
    }
  }

  // 10. Create proposal to transfer 2.76M INCR tokens to the EcosystemReserve
  const governorArtifact = await hre.artifacts.readArtifact("IGovernor");
  const governor = new Contract(
    constants.addresses.L2_GOVERNOR,
    [
      ...governorArtifact.abi,
      {
        type: "function",
        name: "queue",
        inputs: [
          { name: "targets", type: "address[]", internalType: "address[]" },
          { name: "values", type: "uint256[]", internalType: "uint256[]" },
          { name: "calldatas", type: "bytes[]", internalType: "bytes[]" },
          { name: "descriptionHash", type: "bytes32", internalType: "bytes32" },
        ],
        outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
        stateMutability: "nonpayable",
      },
    ],
    wallet
  );
  const ERC20Artifact = await hre.artifacts.readArtifact("ERC20");
  const erc20Interface = new Interface(ERC20Artifact.abi);

  const proposalTargets = [rewardTokenAddress];
  const proposalValues = [0];
  const proposalCalldatas = [
    erc20Interface.encodeFunctionData("transfer", [
      ecosystemReserveAddress,
      parseEther("2760000"),
    ]),
  ];
  const proposalDescription =
    "Transfer 2.76M INCR to EcosystemReserve and enable LP rewards";

  const proposalId = await governor.propose.staticCall(
    proposalTargets,
    proposalValues,
    proposalCalldatas,
    proposalDescription
  );
  const proposalTx = await governor.propose(
    proposalTargets,
    proposalValues,
    proposalCalldatas,
    proposalDescription
  );
  await proposalTx.wait();
  console.log(`Proposal ${proposalId} created with params: `, {
    targets: proposalTargets,
    values: proposalValues,
    calldatas: proposalCalldatas,
    description: proposalDescription,
  });
}
