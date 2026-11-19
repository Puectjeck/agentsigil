// Compile AgentSigil.sol with solc-js (optimizer on) and report sizes.
// Usage: npm run compile
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const root = path.join(__dirname, "..");
const sourcePath = path.join(root, "contracts", "AgentSigil.sol");
const source = fs.readFileSync(sourcePath, "utf8");

const input = {
  language: "Solidity",
  sources: { "AgentSigil.sol": { content: source } },
  settings: {
    viaIR: true,
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode", "evm.deployedBytecode"] } },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input)));

let hasError = false;
for (const e of output.errors || []) {
  console.log(`${e.severity.toUpperCase()}: ${e.formattedMessage}`);
  if (e.severity === "error") hasError = true;
}
if (hasError) process.exit(1);

const c = output.contracts["AgentSigil.sol"]["AgentSigil"];
const creationBytes = Buffer.from(c.evm.bytecode.object, "hex");
const deployedBytes = Buffer.from(c.evm.deployedBytecode.object, "hex");

// Deployment gas estimate (standard Yellow Paper accounting):
//   21,000  transaction intrinsic
// + 32,000  contract creation
// + initcode byte cost (16 / non-zero byte, 4 / zero byte) — creation tx data
// + constructor execution allowance (~25,000: owner SSTORE + overhead)
// + 200 * deployed size (code deposit)
// Execution of the init code beyond the owner SSTORE is minimal (constants
// and immutable-free storage init), so this lands within a few % of actual.
let initByteCost = 0;
for (const b of creationBytes) initByteCost += b === 0 ? 4 : 16;
const codeDeposit = 200 * deployedBytes.length;
const constructorExec = 25000;
const estimatedDeployGas =
  21000 + 32000 + initByteCost + constructorExec + codeDeposit;

const bscGasPriceGwei = 0.05;
const estimatedCostBnb = (estimatedDeployGas * bscGasPriceGwei) / 1e9;

const artifact = {
  contractName: "AgentSigil",
  compiler: solc.version(),
  viaIR: true,
  optimizer: { enabled: true, runs: 200 },
  abi: c.abi,
  bytecode: "0x" + c.evm.bytecode.object,
  deployedBytecode: "0x" + c.evm.deployedBytecode.object,
  sizes: {
    creationBytecodeBytes: creationBytes.length,
    deployedBytecodeBytes: deployedBytes.length,
  },
  estimatedDeployGas,
  estimateBreakdown: { intrinsic: 21000, creation: 32000, initByteCost, constructorExec, codeDeposit },
  estimatedCostBnbAt005Gwei: estimatedCostBnb,
};

const outPath = path.join(root, "build", "AgentSigil.json");
fs.writeFileSync(outPath, JSON.stringify(artifact, null, 2));

console.log("--- AgentSigil compile OK ---");
console.log("compiler:            ", solc.version());
console.log("creation bytecode:   ", creationBytes.length, "bytes");
console.log("deployed bytecode:   ", deployedBytes.length, "bytes");
console.log("estimated deploy gas:", estimatedDeployGas.toLocaleString("en-US"));
console.log("estimated cost @0.05 gwei:", estimatedCostBnb.toFixed(8), "BNB");
console.log("artifact:            ", outPath);
