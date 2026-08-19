require("@nomicfoundation/hardhat-toolbox");
require("@tenderly/hardhat-tenderly");
require("hardhat-abi-exporter");
require("@solidstate/hardhat-bytecode-exporter");
require("dotenv").config();
require("./tasks");

const { buildNetworks } = require("./config/networks");

module.exports = {
  solidity: {
    version: "0.8.29",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 10000
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test/hardhat",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    ...buildNetworks(),
    hardhat: {
      allowUnlimitedContractSize: false
    }
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    only: ["^contracts/"]
  },
  bytecodeExporter: {
    path: "./bin",
    runOnCompile: true,
    clear: true,
    flat: true,
    except: ["contracts/test/"]
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  tenderly: {
    username: process.env.TENDERLY_USERNAME || "",
    project: process.env.TENDERLY_PROJECT || ""
  },
  sourcify: {
    enabled: false
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true"
  }
};
