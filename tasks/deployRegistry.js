const { task } = require("hardhat/config");
const { compile, deployContract, getSigner } = require("./utils");

async function deployRegistry(hre, args = {}) {
  const admin = args.admin || (await getSigner(hre)).address;

  return deployContract(hre, "SwapExecutionRegistry", [admin], { verify: true });
}

task("deploy-registry", "Deploys a new SwapExecutionRegistry")
  .addOptionalParam("admin", "The address of the registry admin (defaults to the deployer)")
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployRegistry(hre, args);
  });

module.exports = { deployRegistry };
