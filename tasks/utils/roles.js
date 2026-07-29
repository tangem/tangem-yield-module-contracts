const { send } = require("./tx");

const DEFAULT_ADMIN_ROLE = `0x${"0".repeat(64)}`;

/** Reads the role hash from the contract itself instead of recomputing keccak256 off-chain. */
async function getRole(contract, roleName) {
  if (roleName === "DEFAULT_ADMIN_ROLE") return DEFAULT_ADMIN_ROLE;

  return contract[roleName]();
}

/** `on` is an optional contract label, used when a task touches several contracts. */
function subject(roleName, preposition, account, on) {
  return `${roleName} ${preposition} ${account}${on ? ` on ${on}` : ""}`;
}

async function grantRoles(hre, contract, roleNames, account, on) {
  for (const roleName of roleNames) {
    const role = await getRole(contract, roleName);
    await send(hre, "grantRole", contract.grantRole(role, account), subject(roleName, "to", account, on));
  }
}

async function revokeRoles(hre, contract, roleNames, account, on) {
  for (const roleName of roleNames) {
    const role = await getRole(contract, roleName);
    await send(hre, "revokeRole", contract.revokeRole(role, account), subject(roleName, "from", account, on));
  }
}

/** Temporarily grants the roles to `account`, runs `fn`, then revokes them back. */
async function withRoles(hre, contract, roleNames, account, fn) {
  await grantRoles(hre, contract, roleNames, account);
  await fn();
  await revokeRoles(hre, contract, roleNames, account);
}

module.exports = { DEFAULT_ADMIN_ROLE, getRole, grantRoles, revokeRoles, withRoles };
