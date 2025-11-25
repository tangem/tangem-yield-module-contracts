require("@nomicfoundation/hardhat-toolbox");
require("hardhat-abi-exporter");
require("@solidstate/hardhat-bytecode-exporter");
require("dotenv").config();

const MNEMONIC = process.env.MNEMONIC;
const ACCOUNTS = MNEMONIC ? { "mnemonic": MNEMONIC, "initialIndex": 0 } : "remote";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

task("deploy-base", "Deploys contracts for testing")
  .addParam("pool", "The address of the Aave pool")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const pool = taskArgs.pool;

    const TangemERC2771Forwarder = await ethers.getContractFactory("TangemERC2771Forwarder");
    const forwarder = await TangemERC2771Forwarder.deploy();
    await forwarder.waitForDeployment();

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = await TangemYieldProcessor.deploy("0x37E7e93093AE3A8AAEf4A0D41DBd9c037508eB60", 1500);
    await processor.waitForDeployment();

    console.log("TangemYieldProcessor deployed to: ", await processor.getAddress());

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = await TangemYieldModuleFactory.deploy();
    await factory.waitForDeployment();

    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const moduleImplementation = await AaveV3YieldModule.deploy(pool, processor, factory, forwarder);
    await moduleImplementation.waitForDeployment();

    const implementationSetterRole = ethers.id("IMPLEMENTATION_SETTER_ROLE")
    const grantTx4 = await factory.grantRole(implementationSetterRole, msgSender);
    await grantTx4.wait();

    const pauserRole = ethers.id("PAUSER_ROLE")
    const grantTx5 = await factory.grantRole(pauserRole, msgSender);
    await grantTx5.wait();

    const setTx = await factory.setImplementation(moduleImplementation);
    await setTx.wait();

    const unpauseTx = await factory.unpause();
    await unpauseTx.wait();

    const revokeTx1 = await factory.revokeRole(implementationSetterRole, msgSender);
    await revokeTx1.wait();

    const revokeTx2 = await factory.revokeRole(pauserRole, msgSender);
    await revokeTx2.wait();

    console.log("TangemYieldModuleFactory deployed to: ", await factory.getAddress());
  });

task("deploy-module", "Deploys yield module")
  .addParam("factory", "The address of the yield module factory")
  .addParam("token", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const factoryAddress = taskArgs.factory;
    const yieldTokenAddress = taskArgs.token;
    const ownerAddress = msgSender;

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress)
    
    const deployTx = await factory.deployYieldModule(ownerAddress, yieldTokenAddress, 100);
    await deployTx.wait();

    const yieldModuleAddress = await factory.yieldModules(ownerAddress);
    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const yieldModule = AaveV3YieldModule.attach(yieldModuleAddress);

    console.log("TangemYieldModule deployed to: " + yieldModuleAddress);

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const yieldToken = TestERC20.attach(yieldTokenAddress);

    const approveTx = await yieldToken.approve(yieldModule, hre.ethers.MaxUint256);
    await approveTx.wait();

    console.log("Yield token approval given");
  });

task("enter-protocol", "Enters yield protocol")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("owner", "The address of the yield module's owner")
  .addParam("token", "The address of the yield token")
  .addParam("maxFee", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const processorAddress = taskArgs.processor;
    const factoryAddress = taskArgs.factory;
    const ownerAddress = taskArgs.owner;
    const yieldTokenAddress = taskArgs.token;
    const maxFee = taskArgs.maxFee;

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress);
    
    const yieldModuleAddress = factory.yieldModules(ownerAddress);

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const enterTx = await processor.enterProtocol(yieldModuleAddress, yieldTokenAddress, maxFee); // , { gasLimit: 3000000 });
    await enterTx.wait();

    console.log("Protocol entered");
  });

task("grant-backend-roles", "Grants backend roles")
  .addParam("processor", "The address of the yield processor")
  .addParam("to", "The address of the account to grant roles to")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const processorAddress = taskArgs.processor;
    const to = taskArgs.to;

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const protocolEntererRole = ethers.id("PROTOCOL_ENTERER_ROLE")
    const grantTx1 = await processor.grantRole(protocolEntererRole, to);
    await grantTx1.wait();

    const serviceFeeCollectorRole = ethers.id("SERVICE_FEE_COLLECTOR_ROLE")
    const grantTx2 = await processor.grantRole(serviceFeeCollectorRole, to);
    await grantTx2.wait();

    console.log("Backend roles granted");
  });

task("change-admin", "Changes the Default Admin for processor and factory")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("to", "The address of the new admin")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address

    const processorAddress = taskArgs.processor;
    const factoryAddress = taskArgs.factory;
    const to = taskArgs.to;

    const TangemYieldProcessor = await ethers.getContractFactory("TangemYieldProcessor");
    const processor = TangemYieldProcessor.attach(processorAddress);
    
    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress);

    const defaultAdminRole = "0x0000000000000000000000000000000000000000000000000000000000000000";
    
    const grantTx1 = await processor.grantRole(defaultAdminRole, to);
    await grantTx1.wait();

    const grantTx2 = await factory.grantRole(defaultAdminRole, to);
    await grantTx2.wait();

    const revokeTx1 = await processor.revokeRole(defaultAdminRole, msgSender);
    await revokeTx1.wait();

    const revokeTx2 = await factory.revokeRole(defaultAdminRole, msgSender);
    await revokeTx2.wait();

    console.log("Admin has been changed");
  });

task("upgrade-module-implementation", "Deploys new module implementation and sets it to factory")
  .addParam("pool", "The address of the Aave pool")
  .addParam("processor", "The address of the yield processor")
  .addParam("factory", "The address of the yield module factory")
  .addParam("forwarder", "The address of the Tangem forwarder")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const msgSender = (await hre.ethers.getSigners())[0].address;

    const poolAddress = taskArgs.pool;
    const processorAddress = taskArgs.processor;
    const factoryAddress = taskArgs.factory;
    const forwarderAddress = taskArgs.forwarder;

    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const moduleImplementation =
      await AaveV3YieldModule.deploy(poolAddress, processorAddress, factoryAddress, forwarderAddress);
    await moduleImplementation.waitForDeployment();

    console.log("New implementation deployed to: ", await moduleImplementation.getAddress());

    const TangemYieldModuleFactory = await ethers.getContractFactory("TangemYieldModuleFactory");
    const factory = TangemYieldModuleFactory.attach(factoryAddress);

    const implementationSetterRole = ethers.id("IMPLEMENTATION_SETTER_ROLE")
    const grantTx1 = await factory.grantRole(implementationSetterRole, msgSender);
    await grantTx1.wait();

    const pauserRole = ethers.id("PAUSER_ROLE")
    const grantTx2 = await factory.grantRole(pauserRole, msgSender);
    await grantTx2.wait();

    const pauseTx = await factory.pause();
    await pauseTx.wait();

    const setTx = await factory.setImplementation(moduleImplementation);
    await setTx.wait();

    const unpauseTx = await factory.unpause();
    await unpauseTx.wait();

    const revokeTx1 = await factory.revokeRole(implementationSetterRole, msgSender);
    await revokeTx1.wait();

    const revokeTx2 = await factory.revokeRole(pauserRole, msgSender);
    await revokeTx2.wait();

    console.log("New implementation set");
  });

task("get-effective-balance", "Withdraws user funds")
  .addParam("module", "The address of the yield module")
  .addParam("token", "The address of the yield token")
  .setAction(async (taskArgs) => {
    await hre.run('compile');

    const yieldModuleAddress = taskArgs.module;
    const yieldTokenAddress = taskArgs.token;

    const AaveV3YieldModule = await ethers.getContractFactory("TangemAaveV3YieldModule");
    const yieldModule = AaveV3YieldModule.attach(yieldModuleAddress);
    
    const effectiveBalance = await yieldModule.effectiveBalance(yieldTokenAddress);

    console.log("Effective balance - ", effectiveBalance);
  });

module.exports = {
  solidity: {
    version: "0.8.29",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000
      }
    }
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true
  },
  bytecodeExporter: {
    path: "./bin",
    runOnCompile: true,
    clear: true,
    flat: true
  },
  networks: {
    ethereum: {
      url: "https://mainnet.gateway.tenderly.co",
      accounts: ACCOUNTS
    },
    avalanche: {
      url: "https://avalanche.drpc.org",
      accounts: ACCOUNTS
    },
    arbitrum: {
      url: "https://arbitrum-one.public.blastapi.io",
      accounts: ACCOUNTS
    },
    optimism: {
      url: "https://optimism.drpc.org",
      accounts: ACCOUNTS
    },
    base: {
      url: "https://base-rpc.publicnode.com",
      accounts: ACCOUNTS
    },
    gnosis: {
      url: "https://gnosis.drpc.org",
      accounts: ACCOUNTS
    },
    bsc: {
      url: "https://bsc.drpc.org",
      accounts: ACCOUNTS
    },
    zksync: {
      url: "https://zksync.drpc.org",
      accounts: ACCOUNTS
    },
    polygon: {
      url: "https://rpc-mainnet.matic.quiknode.pro/",
      accounts: ACCOUNTS
    },
    sonic: {
      url: "https://sonic.drpc.org",
      accounts: ACCOUNTS
    },
    sepolia: {
      url: "https://gateway.tenderly.co/public/sepolia",
      accounts: ACCOUNTS
    },
    arbitrum_sepolia: {
      url: "https://arbitrum-sepolia.drpc.org",
      accounts: ACCOUNTS
    },
    hardhat: {
      allowUnlimitedContractSize: false
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  sourcify: {
    enabled: false
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS == "true"
  }
};
