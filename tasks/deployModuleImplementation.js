const { task } = require("hardhat/config");
const { compile, deployContract } = require("./utils");

async function deployModuleImplementation(hre, args) {
  return deployContract(hre, "TangemAaveV3YieldModule", [
    args.pool,
    args.distributor,
    args.processor,
    args.factory,
    args.forwarder,
    args.registry,
  ]);
}

task("deploy-module-implementation", "Deploys a new yield module implementation")
  .addParam("pool", "The address of the Aave pool")
  .addParam("distributor", "The address of the Merkl distributor")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("forwarder", "The address of the Tangem forwarder")
  .addParam("registry", "The address of the swap execution registry")
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployModuleImplementation(hre, args);
  });

module.exports = { deployModuleImplementation };
