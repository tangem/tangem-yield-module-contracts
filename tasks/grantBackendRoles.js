const { task } = require("hardhat/config");
const { compile, getContract, grantRoles } = require("./utils");

const BACKEND_ROLES = ["PROTOCOL_ENTERER_ROLE", "SERVICE_FEE_COLLECTOR_ROLE"];

async function grantBackendRoles(hre, args) {
  const processor = await getContract(hre, "TangemYieldProcessor", args.processor);

  await grantRoles(hre, processor, BACKEND_ROLES, args.to);
}

task("grant-backend-roles", "Grants the backend roles on the yield processor")
  .addParam("processor", "The address of the yield processor")
  .addParam("to", "The address of the account to grant roles to")
  .setAction(async (args, hre) => {
    await compile(hre);
    await grantBackendRoles(hre, args);
  });

module.exports = { grantBackendRoles };
