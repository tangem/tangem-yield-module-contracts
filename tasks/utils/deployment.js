const deploymentParameters = require("../../config/deployment-parameters.json");

const REQUIRED_PARAMETERS = ["pool", "distributor", "wrappedNative"];

/** Config values of the network, overridden by the CLI arguments that were passed. */
function resolveDeploymentParameters(hre, args = {}, required = REQUIRED_PARAMETERS) {
  const networkName = hre.network.name;
  const { chainId, ...configured } = deploymentParameters[networkName] ?? {};

  if (chainId !== undefined && chainId !== hre.network.config.chainId) {
    throw new Error(
      `Chain ID mismatch for network "${networkName}": expected ${chainId}, got ${hre.network.config.chainId}`,
    );
  }

  const overrides = Object.fromEntries(Object.entries(args).filter(([, value]) => value !== undefined));
  const parameters = { ...configured, ...overrides };
  const missing = required.filter((name) => !parameters[name]);

  if (missing.length > 0) {
    throw new Error(
      `Missing deployment parameters for network "${networkName}": ${missing.join(", ")}. ` +
        "Configure them in config/deployment-parameters.json or pass them as CLI arguments.",
    );
  }

  return parameters;
}

module.exports = { resolveDeploymentParameters };
