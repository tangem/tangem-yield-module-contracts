const fs = require("node:fs/promises");
const path = require("node:path");
const { AaveClient, chainId: toAaveChainId } = require("@aave/client");
const { chains: fetchAaveChains, markets: fetchAaveMarkets } = require("@aave/client/actions");
const { builtinChains } = require("@nomicfoundation/hardhat-verify/internal/chain-config");
const { NETWORKS, rpcUrl } = require("../../config/networks");
const { log, warn } = require("./log");

const NETWORKS_PATH = path.join(__dirname, "../../config/networks.js");
const PARAMETERS_PATH = path.join(__dirname, "../../config/deployment-parameters.json");
const README_PATH = path.join(__dirname, "../../README.md");

const ETHERSCAN_CHAINS_URL = "https://api.etherscan.io/v2/chainlist";
const MERKL_API_URL = "https://api.merkl.xyz/v4";
const MERKL_DISTRIBUTOR = "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae";
const MERKL_PROBE_USER = "0x000000000000000000000000000000000000dEaD";

const README_CONTRACTS = {
  processor: "TangemYieldProcessor",
  factory: "TangemYieldModuleFactory",
  registry: "SwapExecutionRegistry",
};

const NETWORK_NAME_PATTERN = /^[a-z][a-z0-9_]*$/;
const REQUEST_TIMEOUT_MS = 10_000;
const TASK = "initNetwork";

const POOL_ABI = ["function ADDRESSES_PROVIDER() view returns (address)"];
const ADDRESSES_PROVIDER_ABI = ["function getPool() view returns (address)"];
const ERC20_ABI = ["function symbol() view returns (string)"];
const DISTRIBUTOR_ABI = [
  "function tree() view returns (bytes32 merkleRoot, bytes32 ipfsHash)",
  "function lastTree() view returns (bytes32 merkleRoot, bytes32 ipfsHash)",
];

async function fetchJson(url, init = {}) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });

  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);

  return response.json();
}

/** Aave SDK actions return a Result instead of throwing. */
function unwrap(result) {
  if (result.isErr()) throw new Error(`Aave API: ${result.error.message}`);

  return result.value;
}

async function fetchAaveChain(chainId) {
  const client = AaveClient.create();
  const chain = unwrap(await fetchAaveChains(client)).find((candidate) => candidate.chainId === chainId);

  if (!chain) throw new Error(`Aave V3 is not deployed on chain ${chainId}`);
  if (!chain.nativeWrappedToken) throw new Error(`Aave API has no wrapped native token for chain ${chainId}`);

  const markets = unwrap(await fetchAaveMarkets(client, { chainIds: [toAaveChainId(chainId)] }));

  return { ...chain, markets };
}

/** New networks are named after the Aave chain: "BSC" -> bsc, "X Layer" -> x_layer. */
function resolveNetwork(chainId, aaveChain, args) {
  const existingName = Object.keys(NETWORKS).find((name) => NETWORKS[name].chainId === chainId);

  if (existingName) {
    if (args.name && args.name !== existingName) {
      throw new Error(`Chain ${chainId} is already configured as "${existingName}" in config/networks.js`);
    }

    if (args.rpc) {
      throw new Error(
        `"${existingName}" already has an RPC in config/networks.js. ` +
          `Use RPC_URL_${existingName.toUpperCase()} or edit the file to change it`,
      );
    }

    return { name: existingName, rpc: rpcUrl(existingName, NETWORKS[existingName].rpc), isNew: false };
  }

  const name = args.name ?? aaveChain.name.toLowerCase().replaceAll(" ", "_");

  if (!NETWORK_NAME_PATTERN.test(name)) {
    throw new Error(`Network name "${name}" must be snake_case (a-z, 0-9, _). Pass --name`);
  }

  if (NETWORKS[name]) {
    throw new Error(`Network "${name}" is already configured with chain ID ${NETWORKS[name].chainId}. Pass --name`);
  }

  if (!args.rpc) throw new Error(`"${name}" is a new network, pass its RPC URL with --rpc`);

  return { name, rpc: args.rpc, isNew: true };
}

async function connectRpc(hre, rpc, chainId) {
  const request = new hre.ethers.FetchRequest(rpc);
  request.timeout = REQUEST_TIMEOUT_MS;

  const provider = new hre.ethers.JsonRpcProvider(request, chainId, { staticNetwork: true });
  const failure = `RPC ${rpc} is unreachable, rejects eth_call or serves another chain`;

  try {
    if (Number(await provider.send("eth_chainId", [])) !== chainId) throw new Error(failure);

    // Some public RPCs answer eth_chainId but reject eth_call, which every task relies on.
    await provider.send("eth_call", [{ to: hre.ethers.ZeroAddress, data: "0x" }, "latest"]);
  } catch {
    throw new Error(failure);
  }

  return provider;
}

async function assertHasCode(provider, address, label) {
  if ((await provider.getCode(address)) === "0x") throw new Error(`${label} ${address} has no code on this chain`);
}

/** Chains with several Aave markets (Core, Prime, EtherFi...) need an explicit --pool. */
function selectPool(hre, markets, poolOverride) {
  const candidates = poolOverride
    ? markets.filter(({ address }) => address.toLowerCase() === poolOverride.toLowerCase())
    : markets;

  if (candidates.length !== 1) {
    const list = markets.map(({ name, address }) => `${name} ${address}`).join(", ");
    const problem = poolOverride ? `--pool ${poolOverride} is not an Aave market on this chain` : "choose a market with --pool";

    throw new Error(`${problem}. Markets: ${list}`);
  }

  return hre.ethers.getAddress(candidates[0].address);
}

/** The pool must be the one its own PoolAddressesProvider points to. */
async function verifyPool(hre, provider, pool) {
  const addressesProvider = await new hre.ethers.Contract(pool, POOL_ABI, provider).ADDRESSES_PROVIDER();
  const registeredPool = await new hre.ethers.Contract(addressesProvider, ADDRESSES_PROVIDER_ABI, provider).getPool();

  if (registeredPool !== pool) {
    throw new Error(`Aave pool ${pool} is not registered in its PoolAddressesProvider ${addressesProvider}`);
  }

  log(`Aave pool ${pool} matches PoolAddressesProvider ${addressesProvider}`, TASK);
}

async function verifyWrappedNative(hre, provider, wrappedNative) {
  await assertHasCode(provider, wrappedNative, "Wrapped native");

  const symbol = await new hre.ethers.Contract(wrappedNative, ERC20_ABI, provider).symbol();
  log(`wrapped native ${wrappedNative} (${symbol})`, TASK);
}

async function fetchMerklRoot(chainId) {
  const rewards = await fetchJson(`${MERKL_API_URL}/users/${MERKL_PROBE_USER}/rewards?chainId=${chainId}`);

  return rewards.find((entry) => entry.chain.id === chainId)?.rewards[0]?.root;
}

/**
 * Merkl must list the chain, the distributor must hold a live tree, and when the API exposes
 * the chain's current root it must match one of the distributor's on-chain roots.
 */
async function resolveDistributor(hre, provider, chainId, distributorOverride) {
  const response = await fetch(`${MERKL_API_URL}/chains/${chainId}`, { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });

  if (response.status === 404) throw new Error(`Merkl does not support chain ${chainId}`);
  if (!response.ok) throw new Error(`Merkl API returned HTTP ${response.status} for chain ${chainId}`);

  const distributor = hre.ethers.getAddress(distributorOverride ?? MERKL_DISTRIBUTOR);
  await assertHasCode(provider, distributor, "Merkl distributor");

  const contract = new hre.ethers.Contract(distributor, DISTRIBUTOR_ABI, provider);
  const [tree, lastTree] = await Promise.all([contract.tree(), contract.lastTree()]);

  if (tree.merkleRoot === hre.ethers.ZeroHash) {
    throw new Error(`Merkl distributor ${distributor} has no merkle root on this chain`);
  }

  const apiRoot = await fetchMerklRoot(chainId);

  if (!apiRoot) {
    warn("Merkl API exposes no root for this chain, skipped the on-chain root cross-check", TASK);
  } else if (![tree.merkleRoot, lastTree.merkleRoot].includes(apiRoot)) {
    throw new Error(`Merkl API root ${apiRoot} does not match distributor ${distributor} roots`);
  } else {
    log(`Merkl distributor ${distributor} root matches Merkl API`, TASK);
  }

  return distributor;
}

/** Reads the `### <Network> (<chainId>)` section, up to the next heading. */
function parseReadmeDeployment(readme, chainId) {
  const lines = readme.split("\n");
  const start = lines.findIndex((line) => line.startsWith("### ") && line.trimEnd().endsWith(`(${chainId})`));

  if (start === -1) return {};

  const end = lines.findIndex((line, index) => index > start && line.startsWith("#"));
  const section = lines.slice(start + 1, end === -1 ? undefined : end);
  const addresses = {};

  for (const [key, contractName] of Object.entries(README_CONTRACTS)) {
    const prefix = `${contractName} - [`;
    const line = section.find((candidate) => candidate.startsWith(prefix));
    const address = line?.slice(prefix.length, line.indexOf("]"));

    if (address) addresses[key] = address;
  }

  return addresses;
}

async function resolveReadmeAddresses(hre, provider, chainId) {
  const addresses = parseReadmeDeployment(await fs.readFile(README_PATH, "utf8"), chainId);

  if (Object.keys(addresses).length === 0) {
    warn(`README has no deployed contracts for chain ${chainId}`, TASK);
  }

  for (const [key, address] of Object.entries(addresses)) {
    if (!hre.ethers.isAddress(address)) throw new Error(`README ${README_CONTRACTS[key]} "${address}" is not an address`);

    await assertHasCode(provider, address, `README ${README_CONTRACTS[key]}`);
    addresses[key] = hre.ethers.getAddress(address);
  }

  return addresses;
}

/** Advisory only: deployment still works without explorer verification. */
async function checkExplorerVerification(hre, chainId) {
  let chain;

  try {
    chain = (await fetchJson(ETHERSCAN_CHAINS_URL)).result.find(({ chainid }) => Number(chainid) === chainId);
  } catch (error) {
    warn(`could not fetch the Etherscan API v2 chain list: ${error.message}`, TASK);
    return;
  }

  if (!chain) {
    warn(`Etherscan API v2 does not support chain ${chainId}, EXPLORER_VERIFY will fail`, TASK);
    return;
  }

  if (chain.status !== 1) {
    warn(`Etherscan API v2 reports status ${chain.status} for chain ${chainId} (1 = ok)`, TASK);
  }

  const customChains = hre.config.etherscan.customChains ?? [];
  const isKnown = [...builtinChains, ...customChains].some((known) => known.chainId === chainId);

  if (!isKnown) {
    warn(
      `hardhat-verify does not know chain ${chainId}: add etherscan.customChains ` +
        `{ apiURL: "${chain.apiurl}", browserURL: "${chain.blockexplorer}" }`,
      TASK,
    );
    return;
  }

  log(`Etherscan API v2 verification is supported (${chain.chainname})`, TASK);
}

async function addNetworkEntry(name, chainId, rpc) {
  const source = await fs.readFile(NETWORKS_PATH, "utf8");
  const end = source.indexOf("\n};", source.indexOf("const NETWORKS = {"));

  if (end === -1) throw new Error("Could not find the NETWORKS object in config/networks.js");

  const entry = `\n  ${name}: { chainId: ${chainId}, rpc: ${JSON.stringify(rpc)} },`;
  await fs.writeFile(NETWORKS_PATH, source.slice(0, end) + entry + source.slice(end));
  log(`added "${name}" to config/networks.js`, TASK);
}

async function writeDeploymentParameters(name, values) {
  const parameters = JSON.parse(await fs.readFile(PARAMETERS_PATH, "utf8"));
  const previous = parameters[name] ?? {};

  for (const [key, value] of Object.entries(values)) {
    if (previous[key] !== undefined && previous[key] !== value) {
      warn(`${name}.${key}: ${previous[key]} -> ${value}`, TASK);
    }
  }

  parameters[name] = { ...previous, ...values };
  await fs.writeFile(PARAMETERS_PATH, `${JSON.stringify(parameters, null, 2)}\n`);
  log(`wrote "${name}" to config/deployment-parameters.json`, TASK);
}

module.exports = {
  MERKL_DISTRIBUTOR,
  addNetworkEntry,
  checkExplorerVerification,
  connectRpc,
  fetchAaveChain,
  resolveDistributor,
  resolveNetwork,
  resolveReadmeAddresses,
  selectPool,
  verifyPool,
  verifyWrappedNative,
  writeDeploymentParameters,
};
