const { task } = require("hardhat/config");
const { deployModuleImplementation } = require("./deployModuleImplementation");
const { DEFAULT_FEE_RECEIVER, DEFAULT_SERVICE_FEE_RATE, deployProcessor } = require("./deployProcessor");
const { deployRegistry } = require("./deployRegistry");
const { compile, deployContract, getSigner, log, send, withRoles } = require("./utils");

async function deployBase(hre, args) {
  const deployer = (await getSigner(hre)).address;

  const forwarder = await deployContract(hre, "TangemERC2771Forwarder", [], { verify: true });
  const processor = await deployProcessor(hre, args);
  const factory = await deployContract(hre, "TangemYieldModuleFactory", [], { verify: true });
  const registry = await deployRegistry(hre, { admin: deployer });

  const implementation = await deployModuleImplementation(hre, {
    pool: args.pool,
    distributor: args.distributor,
    processor: await processor.getAddress(),
    factory: await factory.getAddress(),
    forwarder: await forwarder.getAddress(),
    registry: await registry.getAddress(),
    wrappedNative: args.wrappedNative,
  });

  await withRoles(hre, factory, ["IMPLEMENTATION_SETTER_ROLE", "PAUSER_ROLE"], deployer, async () => {
    await send(hre, "setImplementation", factory.setImplementation(implementation));
    await send(hre, "unpause", factory.unpause());
  });

  log("deployment complete", "deployBase", hre.network.name);

  return { forwarder, processor, factory, registry, implementation };
}

task("deploy-base", "Deploys the base set of Tangem yield contracts")
  .addParam("pool", "The address of the Aave pool")
  .addParam("distributor", "The address of the Merkl distributor")
  .addParam("wrappedNative", "The address of the wrapped native token")
  .addOptionalParam("feeReceiver", `The address collecting service fees (defaults to ${DEFAULT_FEE_RECEIVER})`)
  .addOptionalParam("serviceFeeRate", `The service fee rate in bps (defaults to ${DEFAULT_SERVICE_FEE_RATE})`)
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployBase(hre, args);
  });

module.exports = { deployBase };
