const { task } = require("hardhat/config");
const { compile, deployContract, resolveDeploymentParameters, withErrorLog } = require("./utils");

const MODULE_IMPLEMENTATION_PARAMETERS = [
  "pool",
  "distributor",
  "processor",
  "factory",
  "registry",
  "wrappedNative",
];

async function deployModuleImplementation(hre, args) {
  return deployContract(hre, "TangemAaveV3YieldModule", [
    args.pool,
    args.distributor,
    args.processor,
    args.factory,
    args.forwarder,
    args.registry,
    args.wrappedNative,
  ], { verify: true });
}

task("deploy-module-implementation", "Deploys a new yield module implementation")
  .addOptionalParam("pool", "Overrides the configured Aave pool address")
  .addOptionalParam("distributor", "Overrides the configured Merkl distributor address")
  .addOptionalParam("processor", "Overrides the configured yield processor address")
  .addOptionalParam("factory", "Overrides the configured yield module factory address")
  .addOptionalParam("registry", "Overrides the configured swap execution registry address")
  .addOptionalParam("wrappedNative", "Overrides the configured wrapped native token address")
  .setAction(withErrorLog("deployModuleImplementation", async (args, hre) => {
    await compile(hre);
    const parameters = resolveDeploymentParameters(hre, args, MODULE_IMPLEMENTATION_PARAMETERS);
    // A zero trusted forwarder disables ERC-2771 meta-transactions.
    await deployModuleImplementation(hre, { ...parameters, forwarder: hre.ethers.ZeroAddress });
  }));

module.exports = { deployModuleImplementation };
