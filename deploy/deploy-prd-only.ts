import { parseEther, MaxUint256, Contract, Interface } from "ethers";
import * as hre from "hardhat";

import { deployContract, getWallet } from "./helpers/utils";
import constants from "./helpers/constants";

export default async function () {
  const wallet = getWallet();
  const deployerAddress = await wallet.getAddress();
  const rewardTokenAddress = constants.addresses.L2_TOKEN;
  const governorAddress = constants.addresses.L2_GOVERNOR;

  // Assuming the EcosystemReserve contract was already deployed with the SM contracts
  // Note: make sure to replace the placeholder address with the actual EcosystemReserve address
  const ecosystemReserveAddress = constants.addresses.ECOSYSTEM_RESERVE;
  const EcosystemReserveArtifact = await hre.artifacts.readArtifact(
    "EcosystemReserve"
  );
  const ecosystemReserveInterface = new Interface(EcosystemReserveArtifact.abi);

  const clearingHouseAddress = constants.addresses.CLEARING_HOUSE;
  const ClearingHouseArtifact = await hre.artifacts.readArtifact(
    "ClearingHouse"
  );
  const clearingHouseInterface = new Interface(ClearingHouseArtifact.abi);
  const clearingHouse = new Contract(
    clearingHouseAddress,
    clearingHouseInterface,
    wallet
  );

  // 1. Deploy PerpRewardDistributor
  const perpRewardDistributor = await deployContract("PerpRewardDistributor", [
    constants.perpRewardParams.initialInflationRate,
    constants.perpRewardParams.initialReductionFactor,
    rewardTokenAddress,
    constants.addresses.CLEARING_HOUSE,
    ecosystemReserveAddress,
    constants.perpRewardParams.earlyWithdrawalThreshold,
    constants.perpRewardParams.rewardWeights,
  ]);
  const perpRewardDistributorAddress = await perpRewardDistributor.getAddress();

  // 2. Grant/renounce GOVERNANCE and EMERGENCY_ADMIN roles for PerpRewardDistributor
  const governanceRole = await clearingHouse.GOVERNANCE();
  const emergencyAdminRole = await clearingHouse.EMERGENCY_ADMIN();
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
      contract: perpRewardDistributor,
      contractName: "PerpRewardDistributor",
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

  // 3. Create proposal to:
  //   - transfer 6.44M INCR tokens to the EcosystemReserve
  //   - approve the PerpRewardDistributor to transfer INCR from the EcosystemReserve
  //   - call `ClearingHouse.addRewardContract` to enable LP rewards
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

  const proposalTargets = [
    rewardTokenAddress,
    ecosystemReserveAddress,
    constants.addresses.CLEARING_HOUSE,
  ];
  const proposalValues = [0, 0, 0];
  const proposalCalldatas = [
    erc20Interface.encodeFunctionData("transfer", [
      ecosystemReserveAddress,
      parseEther("6440000"),
    ]),
    ecosystemReserveInterface.encodeFunctionData("approve", [
      rewardTokenAddress,
      perpRewardDistributorAddress,
      MaxUint256,
    ]),
    clearingHouseInterface.encodeFunctionData("addRewardContract", [
      perpRewardDistributorAddress,
    ]),
  ];
  const proposalDescription =
    "Transfer 6.44M INCR to EcosystemReserve and enable LP rewards";

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
