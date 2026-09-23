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

async function deployContract(hre, contractName, args = [], { verify = false } = {}) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  log(`deployed to ${address}`, contractName, hre.network.name);

  if (verify && !["hardhat", "localhost"].includes(hre.network.name)) {
    const verifications = [];

    if (process.env.EXPLORER_VERIFY === "true") {
      verifications.push((async () => {
        const deploymentTransaction = contract.deploymentTransaction();

        if (deploymentTransaction) {
          await deploymentTransaction.wait(5);
        }

        await hre.run("verify:verify", { address, constructorArguments: args });
      })());
    }

    if (process.env.TENDERLY_VERIFY === "true") {
      verifications.push((async () => {
        const contractData = { name: contractName, address };

        await hre.tenderly.persistArtifacts(contractData);
        await hre.tenderly.verify(contractData);
      })());
    }

    const results = await Promise.allSettled(verifications);
    const errors = results.filter(({ status }) => status === "rejected").map(({ reason }) => reason);

    if (errors.length > 0) {
      throw new AggregateError(errors, `Failed to verify ${contractName}`);
    }
  }

  return contract;
}

async function getContract(hre, contractName, address) {
  const factory = await hre.ethers.getContractFactory(contractName);

  return factory.attach(address);
}

module.exports = { compile, deployContract, getContract, getSigner };
