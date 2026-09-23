const NETWORKS = {
  ethereum: { chainId: 1, rpc: "https://mainnet.gateway.tenderly.co" },
  optimism: { chainId: 10, rpc: "https://optimism.drpc.org" },
  bsc: { chainId: 56, rpc: "https://bsc.meowrpc.com" },
  gnosis: { chainId: 100, rpc: "https://gnosis.drpc.org" },
  polygon: { chainId: 137, rpc: "https://rpc-mainnet.matic.quiknode.pro/" },
  sonic: { chainId: 146, rpc: "https://sonic.drpc.org" },
  zksync: { chainId: 324, rpc: "https://zksync.drpc.org" },
  base: { chainId: 8453, rpc: "https://base-rpc.publicnode.com" },
  arbitrum: { chainId: 42161, rpc: "https://arbitrum-one.public.blastapi.io" },
  avalanche: { chainId: 43114, rpc: "https://avalanche.drpc.org" },
  sepolia: { chainId: 11155111, rpc: "https://gateway.tenderly.co/public/sepolia" },
  arbitrum_sepolia: { chainId: 421614, rpc: "https://arbitrum-sepolia.drpc.org" },
  monad: { chainId: 143, rpc: "https://infra.originstake.com/monad/evm" },
};

/**
 * PRIVATE_KEY takes precedence over MNEMONIC. With neither set, networks get no signers,
 * so read-only tasks still work while write tasks fail with an explicit error.
 */
function accounts() {
  const { PRIVATE_KEY, MNEMONIC } = process.env;

  if (PRIVATE_KEY) return [PRIVATE_KEY];
  if (MNEMONIC) return { mnemonic: MNEMONIC, initialIndex: 0 };

  return [];
}

/** `RPC_URL_<NETWORK>` (uppercased network name) overrides the default public RPC. */
function rpcUrl(name, defaultRpc) {
  return process.env[`RPC_URL_${name.toUpperCase()}`] || defaultRpc;
}

function buildNetworks() {
  const signers = accounts();

  return Object.fromEntries(
    Object.entries(NETWORKS).map(([name, { chainId, rpc }]) => [
      name,
      { chainId, url: rpcUrl(name, rpc), accounts: signers },
    ]),
  );
}

module.exports = { NETWORKS, buildNetworks };
