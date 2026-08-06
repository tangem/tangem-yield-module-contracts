const { task } = require("hardhat/config");
const { compile, getContract, getSigner, send, withRoles } = require("./utils");

async function upgradeModuleImplementation(hre, args) {
  const deployer = (await getSigner(hre)).address;
  const factory = await getContract(hre, "TangemYieldModuleFactory", args.factory);

  await withRoles(hre, factory, ["IMPLEMENTATION_SETTER_ROLE", "PAUSER_ROLE"], deployer, async () => {
    await send(hre, "pause", factory.pause());
    await send(hre, "setImplementation", factory.setImplementation(args.implementation), args.implementation);
    await send(hre, "unpause", factory.unpause());
  });
}

task("upgrade-module-implementation", "Sets a new module implementation on the factory")
  .addParam("factory", "The address of the yield module factory")
  .addParam("implementation", "The address of the new module implementation")
  .setAction(async (args, hre) => {
    await compile(hre);
    await upgradeModuleImplementation(hre, args);
  });

module.exports = { upgradeModuleImplementation };
