const { task } = require("hardhat/config");
const { compile, getContract, send } = require("./utils");

async function enterProtocol(hre, args) {
  const factory = await getContract(hre, "TangemYieldModuleFactory", args.factory);
  const yieldModuleAddress = await factory.yieldModules(args.owner);

  const processor = await getContract(hre, "TangemYieldProcessor", args.processor);

  await send(hre, "enterProtocol", processor.enterProtocol(yieldModuleAddress, args.token, args.maxFee), yieldModuleAddress);
}

task("enter-protocol", "Enters the yield protocol on behalf of a module owner")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("owner", "The address of the yield module's owner")
  .addParam("token", "The address of the yield token")
  .addParam("maxFee", "The maximum network fee")
  .setAction(async (args, hre) => {
    await compile(hre);
    await enterProtocol(hre, args);
  });

module.exports = { enterProtocol };
