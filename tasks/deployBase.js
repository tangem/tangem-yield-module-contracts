const { task } = require("hardhat/config");
const { deployModuleImplementation } = require("./deployModuleImplementation");
const { deployRegistry } = require("./deployRegistry");
const { compile, deployContract, getSigner, log, send, withRoles } = require("./utils");

const DEFAULT_FEE_RECEIVER = "0x37E7e93093AE3A8AAEf4A0D41DBd9c037508eB60";
const DEFAULT_SERVICE_FEE_RATE = 1500;

async function deployBase(hre, args) {
  const deployer = (await getSigner(hre)).address;
  const feeReceiver = args.feeReceiver || DEFAULT_FEE_RECEIVER;
  const serviceFeeRate = args.serviceFeeRate ?? DEFAULT_SERVICE_FEE_RATE;

  const forwarder = await deployContract(hre, "TangemERC2771Forwarder");
  const processor = await deployContract(hre, "TangemYieldProcessor", [feeReceiver, serviceFeeRate]);
  const factory = await deployContract(hre, "TangemYieldModuleFactory");
  const registry = await deployRegistry(hre, { admin: deployer });

  const implementation = await deployModuleImplementation(hre, {
    pool: args.pool,
    distributor: args.distributor,
    processor: await processor.getAddress(),
    factory: await factory.getAddress(),
    forwarder: await forwarder.getAddress(),
    registry: await registry.getAddress(),
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
  .addOptionalParam("feeReceiver", `The address collecting service fees (defaults to ${DEFAULT_FEE_RECEIVER})`)
  .addOptionalParam("serviceFeeRate", `The service fee rate in bps (defaults to ${DEFAULT_SERVICE_FEE_RATE})`)
  .setAction(async (args, hre) => {
    await compile(hre);
    await deployBase(hre, args);
  });

module.exports = { deployBase };
