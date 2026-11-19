// =====================================================================
//  DEPLOY SCRIPT — DO NOT RUN YET.
//
//  Deployment is a separate, explicitly confirmed step. This script
//  refuses to run unless CONFIRM_DEPLOY=YES is set in the environment.
//
//  Intended runner (main session, after Jon confirms the top-up):
//    1. Deployer EOA (Set 1: 0x1F1Cb24B014Ff409d592558D69358FF4DCbfDBe4)
//       funded with ~0.0002 BNB (estimated deploy gas 1,511,424
//       ≈ 0.0000756 BNB at 0.05 gwei, plus buffer).
//    2. DEPLOYER_PRIVATE_KEY passed via environment only — never commit
//       it, never paste it into chat or any file.
//    3. node scripts/deploy.js
//       -> deploys AgentSigil with constructor arg initialOwner =
//          Jon's Binance Agentic Wallet
//          0x4A5944DDf10C5426C39b20b059e340b4E81a98b6
//       -> writes build/deployed.json with the contract address.
// =====================================================================
const fs = require("fs");
const path = require("path");

if (process.env.CONFIRM_DEPLOY !== "YES") {
  console.error("Refusing to deploy: set CONFIRM_DEPLOY=YES only after explicit confirmation.");
  process.exit(1);
}

const { ethers } = require("ethers");

const INITIAL_OWNER = "0x4A5944DDf10C5426C39b20b059e340b4E81a98b6"; // Jon's Agentic Wallet
const RPC = process.env.BSC_RPC || "https://bsc-dataseed1.binance.org";

async function main() {
  const artifact = JSON.parse(
    fs.readFileSync(path.join(__dirname, "..", "build", "AgentSigil.json"), "utf8")
  );
  const provider = new ethers.JsonRpcProvider(RPC, 56);
  const wallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);
  console.log("deployer:", wallet.address);
  console.log("balance:", ethers.formatEther(await provider.getBalance(wallet.address)), "BNB");
  console.log("initialOwner (constructor arg):", INITIAL_OWNER);

  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const contract = await factory.deploy(INITIAL_OWNER);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log("AgentSigil deployed at:", address);
  console.log("owner() read-back:", await contract.owner());

  fs.writeFileSync(
    path.join(__dirname, "..", "build", "deployed.json"),
    JSON.stringify({ address, deployer: wallet.address, initialOwner: INITIAL_OWNER }, null, 2)
  );
}

main().catch((e) => { console.error(e); process.exit(1); });
