const { log } = require("./log");

/** Custom tasks are not compiled automatically, unlike `hardhat test` / `hardhat run`. */
async function compile(hre) {
  await hre.run("compile");
}

async function getSigner(hre) {
  const [signer] = await hre.ethers.getSigners();

  if (!signer) {
    throw new Error("No signer available. Set PRIVATE_KEY or MNEMONIC in .env");
  }

  return signer;
}

async function deployContract(hre, contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();

  log(`deployed to ${await contract.getAddress()}`, contractName, hre.network.name);

  return contract;
}

async function getContract(hre, contractName, address) {
  const factory = await hre.ethers.getContractFactory(contractName);

  return factory.attach(address);
}

module.exports = { compile, deployContract, getContract, getSigner };
