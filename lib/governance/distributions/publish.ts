import * as fs from "fs";
import { config } from "dotenv";
import { toBuffer } from "ethereumjs-util";
import { BigNumber, utils } from "ethers";
import { create } from "ipfs-http-client";
import MerkleTree from "./merkle-tree.js";

config();

const WINDOW_INDEX = 0;

interface Window {
  windowIndex: number;
  totalRewardsDistributed: string;
  merkleRoot: string;
  claims: {
    [key: string]: {
      index: number;
      amount: string;
      proof: string[];
      windowIndex: number;
    };
  };
}

async function main() {
  const csv = fs.readFileSync("distributions/airdrop.csv");
  const data = csv
    .toString()
    .split("\n")
    .map((line) => line.split(","));
  data.pop();
  const window: Window = {
    windowIndex: WINDOW_INDEX,
    totalRewardsDistributed: "0",
    merkleRoot: "",
    claims: {},
  };

  // Create merkle data
  const leaves = data.map((vals, i) =>
    toBuffer(
      utils.solidityKeccak256(
        ["address", "uint256", "uint256"],
        [vals[0], vals[1], i]
      )
    )
  );
  const tree = new MerkleTree(leaves);
  window.merkleRoot = tree.getHexRoot();

  for (let i = 0; i < data.length; i++) {
    let vals = data[i];
    const [address, amount] = vals;
    const proof = tree.getHexProof(leaves[i]);

    window.claims[address] = {
      amount: amount,
      index: i,
      proof: proof,
      windowIndex: WINDOW_INDEX,
    };
    window.totalRewardsDistributed = BigNumber.from(
      window.totalRewardsDistributed
    )
      .add(amount)
      .toString();
  }

  if (Object.keys(window.claims).length !== data.length) {
    throw new Error("Duplicate addresses detected");
  }

  // Store file in repo
  fs.writeFileSync(
    `distributions/window_${WINDOW_INDEX}.json`,
    JSON.stringify(window)
  );

  // Init IPFS client
  const auth =
    "Basic " +
    Buffer.from(
      process.env.INFURA_PROJECT_ID + ":" + process.env.INFURA_KEY_SECRET
    ).toString("base64");
  const ipfs = create({
    host: "ipfs.infura.io",
    port: 5001,
    protocol: "https",
    headers: {
      authorization: auth,
    },
  });

  // Upload to IPFS
  const { cid } = await ipfs.add(JSON.stringify(window), {
    pin: true,
  });
  console.log(`Uploaded to IPFS: ${cid.toString()}`);
}

main().then(() => {
  console.log("Done");
});

export default main;
