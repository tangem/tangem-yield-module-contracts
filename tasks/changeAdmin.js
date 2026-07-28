const { task } = require("hardhat/config");
const { compile, getContract, getSigner, grantRoles, revokeRoles } = require("./utils");

const ADMIN_ROLE = ["DEFAULT_ADMIN_ROLE"];

async function changeAdmin(hre, args) {
  const currentAdmin = (await getSigner(hre)).address;

  const processor = await getContract(hre, "TangemYieldProcessor", args.processor);
  const factory = await getContract(hre, "TangemYieldModuleFactory", args.factory);

  await grantRoles(hre, processor, ADMIN_ROLE, args.to, "the processor");
  await grantRoles(hre, factory, ADMIN_ROLE, args.to, "the factory");

  // Revoked only after both grants succeed, so a failure never leaves a contract without an admin
  await revokeRoles(hre, processor, ADMIN_ROLE, currentAdmin, "the processor");
  await revokeRoles(hre, factory, ADMIN_ROLE, currentAdmin, "the factory");
}

task("change-admin", "Changes the default admin of the processor and the factory")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("to", "The address of the new admin")
  .setAction(async (args, hre) => {
    await compile(hre);
    await changeAdmin(hre, args);
  });

module.exports = { changeAdmin };
