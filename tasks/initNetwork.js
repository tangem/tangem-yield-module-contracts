const { task, types } = require("hardhat/config");
const {
  MERKL_DISTRIBUTOR,
  addNetworkEntry,
  checkExplorerVerification,
  connectRpc,
  fetchAaveChain,
  log,
  resolveDistributor,
  resolveNetwork,
  resolveReadmeAddresses,
  selectPool,
  verifyPool,
  verifyWrappedNative,
  withErrorLog,
  writeDeploymentParameters,
} = require("./utils");

const TASK = "initNetwork";

async function initNetwork(hre, args) {
  const { chainId } = args;
  const aaveChain = await fetchAaveChain(chainId);
  const { name, rpc, isNew } = resolveNetwork(chainId, aaveChain, args);
  const provider = await connectRpc(hre, rpc, chainId);

  log(`network "${name}" (chain ${chainId}) via ${rpc}`, TASK);

  // Resolve and check everything before touching any file, so a failure leaves the config intact.
  const pool = selectPool(hre, aaveChain.markets, args.pool);
  await verifyPool(hre, provider, pool);

  const wrappedNative = hre.ethers.getAddress(aaveChain.nativeWrappedToken);
  await verifyWrappedNative(hre, provider, wrappedNative);

  const distributor = await resolveDistributor(hre, provider, chainId, args.distributor);
  const readmeAddresses = await resolveReadmeAddresses(hre, provider, chainId);

  await checkExplorerVerification(hre, chainId);

  if (isNew) await addNetworkEntry(name, chainId, rpc);

  const values = { chainId, pool, distributor, wrappedNative, ...readmeAddresses };
  await writeDeploymentParameters(name, values);

  return { name, values };
}

task("init-network", "Adds a chain to config/networks.js and config/deployment-parameters.json")
  .addParam("chainId", "The chain ID to initialize", undefined, types.int)
  .addOptionalParam("name", "Network name for a new chain (defaults to the Aave chain name)")
  .addOptionalParam("rpc", "RPC URL, required for a chain missing from config/networks.js")
  .addOptionalParam("pool", "Aave pool to use when the chain has several Aave markets")
  .addOptionalParam("distributor", `Overrides the Merkl distributor address (defaults to ${MERKL_DISTRIBUTOR})`)
  .setAction(withErrorLog(TASK, async (args, hre) => {
    await initNetwork(hre, args);
  }));

module.exports = { initNetwork };
